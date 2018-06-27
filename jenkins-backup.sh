#!/bin/bash -xe

##################################################################################
function usage(){
  echo "usage: $(basename $0) /path/to/jenkins_home archive.tar.gz"
}
##################################################################################

readonly JENKINS_HOME=$1
readonly DEST_FILE=$2
readonly CUR_DIR=$(cd $(dirname ${BASH_SOURCE:-$0}); pwd)
readonly TMP_DIR="$CUR_DIR/tmp"
readonly ARC_NAME="jenkins-backup"
readonly ARC_DIR="$TMP_DIR/$ARC_NAME"
readonly TMP_TAR_NAME="$TMP_DIR/archive.tar.gz"
readonly JOB_CONFIG_ONLY="$CUR_DIR/jobs-config-only.txt"

if [ -z "$JENKINS_HOME" -o -z "$DEST_FILE" ] ; then
    usage >&2
    exit 1
fi

# read in jobs-config-only file (this only works in bash 4.x)
readarray -t jobs_config_only < $JOB_CONFIG_ONLY

rm -rf "$ARC_DIR" "$TMP_TAR_NAME"
for i in config-history fingerprints plugins jobs users secrets nodes userContent workflow-libs;do
    mkdir -p "$ARC_DIR"/$i
done

cp "$JENKINS_HOME/"*.xml "$ARC_DIR"

cp "$JENKINS_HOME/"secret.key* "$ARC_DIR"

if [ "$(ls -A $JENKINS_HOME/config-history/)" ]; then
    cp -R "$JENKINS_HOME/config-history/". "$ARC_DIR/config-history"
fi

if [ "$(ls -A $JENKINS_HOME/fingerprints/)" ]; then
    cp -R "$JENKINS_HOME/fingerprints/". "$ARC_DIR/fingerprints"
fi

cp "$JENKINS_HOME/plugins/"*.[hj]pi "$ARC_DIR/plugins"
hpi_pinned_count=$(find $JENKINS_HOME/plugins/ -name *.hpi.pinned | wc -l)
jpi_pinned_count=$(find $JENKINS_HOME/plugins/ -name *.jpi.pinned | wc -l)
if [ $hpi_pinned_count -ne 0 -o $jpi_pinned_count -ne 0 ]; then
    cp "$JENKINS_HOME/plugins/"*.[hj]pi.pinned "$ARC_DIR/plugins"
fi

if [ "$(ls -A $JENKINS_HOME/users/)" ]; then
    cp -R "$JENKINS_HOME/users/". "$ARC_DIR/users"
fi

if [ "$(ls -A $JENKINS_HOME/secrets/)" ] ; then
    cp -R "$JENKINS_HOME/secrets/". "$ARC_DIR/secrets"
fi

if [ "$(ls -A $JENKINS_HOME/nodes/)" ] ; then
    cp -R "$JENKINS_HOME/nodes/". "$ARC_DIR/nodes"
fi

if [ "$(ls -A $JENKINS_HOME/userContent/)" ] ; then
    cp -R "$JENKINS_HOME/userContent/". "$ARC_DIR/userContent"
fi

if [ "$(ls -A $JENKINS_HOME/workflow-libs/)" ] ; then
    cp -R "$JENKINS_HOME/workflow-libs/". "$ARC_DIR/workflow-libs"
fi

function backup_jobs {
    local run_in_path=$1
    local rel_depth=${run_in_path#$JENKINS_HOME/jobs/}
    if [ -d "$run_in_path" ]; then
        cd "$run_in_path"
        find . -maxdepth 1 -type d | while read full_job_name ; do
            [ "$full_job_name" = "." ] && continue
            [ "$full_job_name" = ".." ] && continue
            job_name=${full_job_name##./}
            if [ -d "$JENKINS_HOME/jobs/$rel_depth/$job_name" ] &&
               [ -f "$JENKINS_HOME/jobs/$rel_depth/$job_name/config.xml" ] &&
               [ "$(grep -c "com.cloudbees.hudson.plugins.folder.Folder" "$JENKINS_HOME/jobs/$rel_depth/$job_name/config.xml")" -ge 1 ] ; then
                echo "Folder! $JENKINS_HOME/jobs/$rel_depth/$job_name/jobs"
                # create folder and copy *.xml config files
                mkdir -p "$ARC_DIR/jobs/$rel_depth/$job_name/"
                find "$JENKINS_HOME/jobs/$rel_depth/$job_name/" -maxdepth 1 -name "*.xml" -print0 | xargs -0 -I {} cp {} "$ARC_DIR/jobs/$rel_depth/$job_name/"
                # since this is a Folder, backup its jobs folder
                backup_jobs "$JENKINS_HOME/jobs/$rel_depth/$job_name/jobs"
            else
                # regular job folder, check if copy config only
                if [[ " ${jobs_config_only[*]} " == *"$job_name"* ]] ; then
                    echo "Only copying job configs, not builds"
                    [ -d "$JENKINS_HOME/jobs/$rel_depth/$job_name" ] && mkdir -p "$ARC_DIR/jobs/$rel_depth/$job_name/"
                    find "$JENKINS_HOME/jobs/$rel_depth/$job_name/" -maxdepth 1 -name "*.xml" -print0 | xargs -0 -I {} cp {} "$ARC_DIR/jobs/$rel_depth/$job_name/"
                else
                    echo "Copying whole job folder"
                    cp -R "$JENKINS_HOME/jobs/$rel_depth/$job_name" "$ARC_DIR/jobs/$rel_depth"
                fi
                true
                echo "Job! $JENKINS_HOME/jobs/$rel_depth/$job_name"
            fi
        done
        echo "Done in $(pwd)"
        cd -
    fi
}

if [ "$(ls -A $JENKINS_HOME/jobs/)" ] ; then
    backup_jobs "$JENKINS_HOME/jobs/"
    # backup job build history as well
    # cp -R "$JENKINS_HOME/jobs/". "$ARC_DIR/jobs"
fi

cd "$TMP_DIR"
tar -czvf "$TMP_TAR_NAME" "$ARC_NAME/"*
cd -
mv -f "$TMP_TAR_NAME" "$DEST_FILE"
rm -rf "$ARC_DIR"

exit 0
