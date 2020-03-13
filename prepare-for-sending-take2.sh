#!/bin/bash
# This script rebases the sof-dev-rebase and modifies the 
# signed-off-by/reviewed-by tags for the commits in the range as follows:
# 1. If the commit already has a Signed-off-by tag for the current user,
#    nothing is done
# 2. If the commit has a Reviewed-by tag for the current user,
#    it is replaced with a Signed-off-by tag at the end
# 3. If neither 1. or 2. are true, Sign-off is added for the current user
#
# It works best when preparing the top "n" patches in the sof-dev-rebase branch
# I am yet to try it with other commit ranges
# At termination the script creates a new branch named sof-dev-rebase-prepare

# Usage: ./prepare-for-sending.sh commit_range
# commit_range should be start_commit..end_commit

old_branch=`git rev-parse --abbrev-ref HEAD`

git checkout -b tmp_branch
start_commit=`cut -d "." -f 1 <<< "$1"`
echo $start_commit
git reset --hard $start_commit

commit_message=`git log --format=%B -n1`

IFS=''
lines=( )
while read -r line; do
  lines+=( "$line" )
done <<< ${commit_message}

new_commit_message="\""

for line in "${lines[@]}"
do
	new_commit_message="${new_commit_message}${line}\n"
done

new_commit_message="${new_commit_message}\""

git rebase HEAD~1 -x 'git commit --amend -m "$(echo '"$new_commit_message"')"'

old_parent=`git log --oneline -n1 | awk '{print $1}'`

git log --oneline $1 > log.txt
cat log.txt
cat log.txt | awk '{print $1}' > commits.txt
cat commits.txt
IFS=$'\n' read -d '' -r -a commits < commits.txt

#get current user email
user_email=`git config user.email`
user_name=`git config user.name`
sign_off="Signed-off-by: ${user_name} <${user_email}>"

for (( idx=${#commits[@]}-1 ; idx>=0 ; idx-- ))
do
	commit=${commits[idx]}
	echo "processing..."${commit}

	new_commit_message="\""
	found=0
	sign_offs=""

	git cherry-pick $commit
	commit_message=`git log --format=%B -n1 $commit`

	IFS=''
	lines=( )
	while read -r line; do
	  lines+=( "$line" )
	done <<< ${commit_message}

	for line in "${lines[@]}"
	do
		#check if the current user's email is on the current line
		if [[ $line == *"${user_email}"*  && $line != *"From"* ]]; then
			tag=`echo $line | awk '{print $1}'`
			if [[ $tag == "Signed-off-by:" ]]; then
				found=1
				sign_offs="${sign_offs}${line}\n"
			else
				if [[ $tag == "Reviewed-by:" ]]; then
					#Replace with Signed-off-by
					found=1
					newline=`echo "${line/Reviewed/"Signed-off"}"`
					sign_offs="${sign_offs}${newline}\n"
				fi
			fi
		else
			if [[ $line == *"Signed-off-by"* ]]; then
				sign_offs="${sign_offs}${line}\n"
			else
				new_commit_message="${new_commit_message}${line}\n"
			fi
		fi
	done

	if [[ $found -eq 0 ]]; then
		sign_offs="${sign_offs}${sign_off}\n"
	fi

	# Add the sign-offs
	new_commit_message="${new_commit_message}${sign_offs}"
	new_commit_message="${new_commit_message}\""

	#echo "${new_commit_message}"

	git rebase HEAD~1 -x 'git commit --amend -m "$(echo '"$new_commit_message"')"'
done

until=`git log --oneline -n1 | awk '{print $1}'`
echo $old_parent
echo $start_commit
echo $until

# checkout to prev branch
git checkout $old_branch

#rebase
git rebase --onto $start_commit $old_parent $until

git checkout -b sof-dev-rebase-prepare

git branch -D tmp_branch
