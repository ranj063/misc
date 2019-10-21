#!/bin/bash
#
# This script lets you automatically get the approvals from a github Pull Request
# and add the Reviewed-by tag to all the commits.
#
# Pre-requirements:
# 1. sudo apt-get install jq
# 2. snap install hub
# 3. Generate a personal access token on github (select repo and user) and save it somewhere.
#
# Usage:
# ./add-pr-reviewed-by.sh PR_NUMBER GITHUB_TOKEN

PR_NUM=$1

#get emails of users who approved the PR
url="https://api.github.com/repos/thesofproject/linux/pulls/"$PR_NUM"/reviews"
curl -H "Authorization: token $2" $url | jq -r '[.[] | select(.state=="APPROVED") | {user: .user.login}]' > users.json
userarray=`cat users.json | jq -r '[.[] | join(",")] | @csv'`
IFS=',' read -r -a hubuser <<< "$userarray"

num_approvals=${#hubuser[@]}

if [ $num_approvals == 0 ]
then
	echo "No approvals for PR"$1
	exit
fi

emails=""
fullnames=""
for element in "${hubuser[@]}"
do
	github_name="${element%\"}"
	github_name="${github_name#\"}"
	url="https://api.github.com/users/"$github_name
	email=`curl -H "Authorization: token $2" $url | jq '.email'`
	fullname=`curl -H "Authorization: token $2" $url | jq '.name'`

	#remove the quotes
	github_email="${email%\"}"
	github_email="${github_email#\"}"
	fullname="${fullname%\"}"
	fullname="${fullname#\"}"

	#skip if name or github email is not set
	if [[ "$github_email" == "null" ]] || [[ $fullname == "null" ]]
	then
		continue
	fi

	if [[ -z "$github_email" ]] || [[ -z $fullname ]]
	then
		continue
	fi

	emails="${emails},${github_email}"
	fullnames="${fullnames},${fullname}"
done

#remove the comma at the beginning
emails="${emails%\"}"
fullnames="${fullnames%\"}"

#split emails into array
IFS=',' read -r -a email_array <<< "$emails"
IFS=',' read -r -a fullname_array <<< "$fullnames"

#create the Reviewed-by string to be added to commits
reviewed=""
i=0
for element in "${email_array[@]}"
do
	if [ ! -z "$element" ]
	then
		if [ ! -z "$reviewed" ]
		then
			reviewed=${reviewed}$"\nReviewed-by: "${fullname_array[$i]}" <"$element">"
		else
			reviewed="\"\nReviewed-by: "${fullname_array[$i]}" <"$element">"
		fi
	fi
	i=$i+1
done
reviewed=$reviewed"\""

#count the number of commits
url="https://api.github.com/repos/thesofproject/linux/pulls/"$1"/commits"
curl -H "Authorization: token $2" $url | jq -r '[.[] | {sha: .sha}]' > commits.json
num_commits=`cat commits.json | jq '. | length'`

#checkout pull request
branch_name="pr"$PR_NUM
pull_head="pull/"$PR_NUM"/head"
git fetch thesofproject $pull_head:$branch_name
git checkout $branch_name

#add reviewed-by 
git rebase HEAD~$num_commits -x 'git commit --amend -m "$(git log --format=%B -n1)$(echo '"$reviewed"')"'

#get the PR branch
url="https://api.github.com/repos/thesofproject/linux/pulls/"$PR_NUM
repo_name=`curl -H "Authorization: token $2" $url | jq '.head.repo.full_name'`
pr_branch=`curl -H "Authorization: token $2" $url | jq '.head.ref'`

#remove the quotes
repo_name="${repo_name%\"}"
repo_name="${repo_name#\"}"
pr_branch="${pr_branch%\"}"
pr_branch="${pr_branch#\"}"

branch_url="https://github.com/"$repo_name"/"$pr_branch
repo_url="https://github.com/"$repo_name

#force push the changes
if `git push -f $repo_url $branch_name:$pr_branch`
then
	echo "Updated PR branch "$pr_branch" successfully"
else
	echo "Permissed denied to update "$repo_url". Aborting merge"
	exit
fi

sleep 5

#merge the PR now
export GITHUB_TOKEN=$2
hub api -XPUT "repos/thesofproject/linux/pulls/$PR_NUM/merge" -f merge_method=rebase

#remove the json files
rm commits.json
rm users.json
