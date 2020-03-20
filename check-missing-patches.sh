#!/bin/bash
#
# This script takes 2 directories as input.
# The first argument pointing to thesofproject/topic/sof-dev branch
# Please checkout the topic/sof-dev to the commit from the release document
# The second directory is the directory to the chrome backport,
# which is what we're checking for missing patches.
#
# Usage: ./check-missong-patches.sh <topic/sof-dev dir> <chrome dir>
#
# The list of missing patches (from topic/sof-dev) are written out to missing_patches.txt

#find files that differ between the 2 input directories
diff_output=`diff -q -r $1/sound/soc/sof $2/sound/soc/sof | grep differ`

IFS=$'\n' read -d '' -r -a files <<< $diff_output
current_dir=`pwd`

rm missing_patches.txt

for file in "${files[@]}"
do
	IFS=$' ' read -d '' -r -a fields <<< $file
	file=${fields[1]}

	# remove the directory prefix to get the file path
	file=${file#"$1/"}

	echo "Processing differences in file "$file"..."

	# change dir to the first input directory
	cd $1
	git log --oneline $file > $current_dir"/log1.txt"

	# switch back to starting directory
	cd $current_dir

	# change dir to the second directory
	cd $2
	git log --oneline $file > $current_dir"/log2.txt"

	# switch back to the starting directory
	cd $current_dir

	# get the list of patches in an array
	IFS=$'\n' read -d '' -r -a patches1 < $current_dir"/log1.txt"
	IFS=$'\n' read -d '' -r -a patches2 < $current_dir"/log2.txt"

	# check which patches in $1 dont exist in $2
	for patch1 in "${patches1[@]}"
	do

		#skip merge commits, squash commits or patches that arent meant for upstream
		if [[ $patch1  == *"Merge"* || $patch1 == *"NOT FOR UPSTREAM"* || $patch1 == *"SQUASH"* ]]; then
			continue
		fi

		# extract commit title
		found=0
		commit_hash=`echo $patch1 | awk '{print $1}'`
		commit_title=${patch1#"$commit_hash "}

		# check if the commit exists in the second repo
		for patch2 in "${patches2[@]}"
		do
			if [[ $patch2 == *$commit_title* ]]; then
				found=1
				break
			fi
		done

		# patch missing from $2, add it to the list of missing patches
		if [[ found -eq 0 ]]; then
			echo "${patch1}" >> missing_patches.txt	
		fi
	done

	#remove the temp logs
	rm log1.txt
	rm log2.txt
done

echo "Done processing all files. Please check missing_patches.txt"
