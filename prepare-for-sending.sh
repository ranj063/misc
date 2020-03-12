#!/bin/bash
# This script generates the patches that are being sent out
# and modifies the signed-off-by/reviewed-by tags as follows:
# 1. If the commit already has a Signed-off-by tag for the current user,
#    nothing is done
# 2. If the commit has a Reviewed-by tag for the current user,
#    it is replaced with a Signed-off-by tag at the end
# 3. If neither 1. or 2. are true, Sign-off is added for the current user

# Usage: ./prepare-for-sending.sh commit_range
# commit_range should be start_commit..end_commit
: $(git format-patch $1)
ls *.patch > patches.txt

IFS=$'\n' read -d '' -r -a patches < patches.txt

for patch in "${patches[@]}"
do
	echo "processing..."${patch}
	IFS=''
	lines=( )
	while read -r line; do
	  lines+=( "$line" )
	done < ${patch}

	found=0
	reviewed=0

	#get current user email
	user_email=`git config user.email`
	user_name=`git config user.name`
	sign_off="Signed-off-by: ${user_name} <${user_email}>"

	new_commit_message=""
	line_count=0
	found=0
	reviewed=0

	for line in "${lines[@]}"
	do
		#check if we're at the end of all signoffs
		if [[ $line == "---" ]]; then
			if [ $found -eq 0 ]; then
				echo ${sign_off} >> output.txt
			else
				if [ $reviewed -eq 1 ]; then
					echo ${newline} >> output.txt
				fi
			fi
		fi
		#check if the current user's email is on the current line
		if [[ $line == *"${user_email}"*  && $line != *"From"* ]]; then
			found=1
			tag=`echo $line | awk '{print $1}'`
			if [[ $tag == "Signed-off-by:" ]]; then
				echo ${line} >> output.txt
			else
				if [[ $tag == "Reviewed-by:" ]]; then
					reviewed=1
					#Replace with Signed-off-by
					newline=`echo "${line/Reviewed/"Signed-off"}"`
				fi
			fi
		else
			echo $line >> output.txt
		fi
	done

	rm $patch
	mv output.txt $patch
	rm output.txt
done

rm patches.txt
