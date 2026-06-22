#!/bin/sh

# Loop through each subdirectory in /mnt/data/cicd/cqs290//cicd_cqs290_master and run the run.sh script if it exists
for dir in /mnt/data/cicd/cqs290//cicd_cqs290_master/*; do
  if [ -d "$dir" ]; then
    if [ -x "$dir/run.sh" ]; then
      echo "Running $dir/run.sh"
      "$dir/run.sh" &
    else
      echo "No executable run.sh found in $dir"
    fi
  fi
done

# Wait for all background jobs to finish
wait
