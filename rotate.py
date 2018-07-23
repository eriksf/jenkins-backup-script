from datetime import datetime, timedelta
import re
import boto3
import click
import click_log
import logging


logger = logging.getLogger(__name__)
click_log.basic_config(logger)
with open('VERSION') as x: __version__ = x.read()


def rotate(key_prefix, key_ext, bucket_name, daily_backups=7, weekly_backups=4, aws_key=None, aws_secret=None, dry_run=False):
    """ Delete old files we've uploaded to S3 according to grandfather, father, sun strategy """

    if dry_run:
        logger.info('Dry run, backup files will actually be rotated/deleted!')

    session = boto3.Session(
        aws_access_key_id=aws_key,
        aws_secret_access_key=aws_secret
    )
    s3 = session.resource('s3')
    bucket = s3.Bucket(bucket_name)
    keys = bucket.objects.filter(Prefix=key_prefix)

    regex = '{0}-(?P<year>[\d]{{4}})(?P<month>[\d]{{2}})(?P<day>[\d]{{2}})-.*{1}'.format(key_prefix, key_ext)
    backups = []

    for key in keys:
        match = re.match(regex, str(key.key))
        if not match:
            continue
        year = int(match.group('year'))
        month = int(match.group('month'))
        day = int(match.group('day'))
        key_date = datetime(year, month, day)
        backups[:0] = [{'key': key.key, 'date': key_date}]
    backups = sorted(backups, key=lambda backup: backup['date'], reverse=True)

    logger.debug('Number of backups: {}'.format(len(backups)))
    if len(backups) > daily_backups+1 and backups[daily_backups]['date'] - backups[daily_backups+1]['date'] < timedelta(days=7):
        key = bucket.Object(backups[daily_backups]['key'])
        logger.info("deleting {0}".format(key))
        if not dry_run:
            key.delete()
            del backups[daily_backups]

    month_offset = daily_backups + weekly_backups
    if len(backups) > month_offset+1 and backups[month_offset]['date'] - backups[month_offset+1]['date'] < timedelta(days=30):
        key = bucket.Object(backups[month_offset]['key'])
        logger.info("deleting {0}".format(key))
        if not dry_run:
            key.delete()
            del backups[month_offset]


@click.command()
@click.version_option(__version__)
@click_log.simple_verbosity_option(logger)
@click.option('-b', '--bucket', 'bucket', required=True, help='The S3 bucket')
@click.option('-p', '--prefix', 'prefix', default='jenkins-backup', help='The prefix (key) of the backup file (Default: jenkins-backup).')
@click.option('-e', '--extension', 'extension', default='.tar.gz', help='The file extension of the backup file (Default: .tar.gz).')
@click.option('-d', '--dry-run', 'dry_run', is_flag=True, default=False, help='Only show how backups would rotate.')
def main(bucket, prefix, extension, dry_run):
    rotate(prefix, extension, bucket, dry_run=dry_run)


if __name__ == '__main__':
    main()
