#!/bin/bash
#
# This script lets you automatically get the approvals from a github Pull Request
# and add the Reviewed-by tag to all the commits in the range requested.
# This script should be run before the weekly upstream merge while aligning
# the sof-dev and sof-dev-rebase branches. It cherrypicks the patches in the commit
# range to sof-dev-rebase and amends their commit message to add the Reviewed-by tags
# based on the the github PR info. 
#
# Pre-requirements:
# 1. sudo apt-get install jq
# 2. snap install hub
# 3. Generate a personal access token on github (select repo and user) and save it somewhere.
#
# Usage:
#commit range should be start_commit..end_commit meaning the start_commit is not included
# ./github-graphql-query.sh GITHUB_TOKEN commit_range

#get commit SHA1s in an array
git log --oneline $2 > log.txt
cat log.txt
cat log.txt | awk '{print $1}' > commits.txt
cat commits.txt

IFS=$'\n' read -d '' -r -a commits < commits.txt

#cherry-pick each commit while getting their reviewed-by tags
for SHA in "${commits[@]}"
do
	script='query {
	  repository(name: \"linux\", owner: \"thesofproject\") {
	    commit: object(expression: \"'${SHA}'\") {
	      ... on Commit {
		associatedPullRequests(first: 1) {
		  edges {
		    node {
		      title
		      number
		    }
		  }
		}
	      }
	    }
	  }
	}'

	script="$(echo $script)"

	#get PR number from SHA
	curl -H "Authorization: token $1" -X POST \
	-d "{ \"query\": \"$script\"}" \
	https://api.github.com/graphql | jq '.data.repository.commit.associatedPullRequests.edges' > node.json
	PR_NUM=`cat node.json | jq -r '[.[] | .node.number] | .[]'`

	#get emails of users who approved the PR
	url="https://api.github.com/repos/thesofproject/linux/pulls/"$PR_NUM"/reviews"
	curl -H "Authorization: token $1" $url | jq -r '[.[] | select(.state=="APPROVED") | {user: .user.login}]' > users.json
	userarray=`cat users.json | jq -r '[.[] | join(",")] | @csv'`
	IFS=',' read -r -a hubuser <<< "$userarray"

	num_approvals=${#hubuser[@]}

	if [ $num_approvals == 0 ]
	then
		echo "No approvals for PR"$PR_NUM
		exit
	fi

	echo "Number of approvals: '$num_approvals'"

	emails=""
	fullnames=""
	for element in "${hubuser[@]}"
	do
		github_name="${element%\"}"
		github_name="${github_name#\"}"
		url="https://api.github.com/users/"$github_name
		email=`curl -H "Authorization: token $1" $url | jq '.email'`
		fullname=`curl -H "Authorization: token $1" $url | jq '.name'`

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

	#cherry-pick and amend commit to add reviewed-by tags
	git cherry-pick $SHA
	git rebase HEAD~1 -x 'git commit --amend -m "$(git log --format=%B -n1)$(echo '"$reviewed"')"'
done

rm users.json
rm node.json
rm log.txt
rm commits.txt