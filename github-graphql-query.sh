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

# List of Intel Linux developers whose email address should be fixed up from
# @intel.com to @linux.intel.com
intel_linux_developers=(
	"pierre-louis.bossart@intel.com"	"pierre-louis.bossart@linux.intel.com"
	"ranjani.sridharan@intel.com"		"ranjani.sridharan@linux.intel.com"
	"fred.oh@intel.com"			"fred.oh@linux.intel.com"
	"guennadi.liakhovetski@intel.com"	"guennadi.liakhovetski@linux.intel.com"
	"kai.vehmanen@intel.com"		"kai.vehmanen@linux.intel.com"
	"jaska.uimonen@intel.com"		"jaska.uimonen@linux.intel.com"
	"seppo.ingalsuo@intel.com"		"seppo.ingalsuo@linux.intel.com"
	"peter.ujfalusi@intel.com"		"peter.ujfalusi@linux.intel.com"
	"bard.liao@intel.com"			"yung-chuan.liao@linux.intel.com"
)

github_email_fixup() {
	let devs="${#intel_linux_developers[@]} / 2"
	declare -n ret=$2

	for (( i=0; i<${devs}; i++ ));
	do
		let "dev_idx=$i*2"
		if [[ $1 == ${intel_linux_developers[$dev_idx]} ]]
		then
			ret=${intel_linux_developers[$dev_idx+1]}
			return 0
		fi
	done
}

if [[ $# != 2 ]]
then
	echo "Missing commit or commit range."
	exit 1
fi

# get commit SHA1s in an array
if [[ $2 == *".."* ]]
then
	# a range is given
	git log --reverse --oneline $2 > log.txt
	echo "Commits to pick:"
else
	# single commit to pick
	git log -1 --oneline $2 > log.txt
	echo "Commit to pick:"
fi

cat log.txt
cat log.txt | awk '{print $1}' > commits.txt

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
	curl -s -H "Authorization: token $1" -X POST \
	-d "{ \"query\": \"$script\"}" \
	https://api.github.com/graphql | jq '.data.repository.commit.associatedPullRequests.edges' > node.json
	PR_NUM=`cat node.json | jq -r '[.[] | .node.number] | .[]'`
	PR_TITLE=`cat node.json | jq -r '[.[] | .node.title] | .[]'`

	echo ""
	echo "-----------------------------------------------"
	git log --pretty='short' -1 ${SHA} | cat
	echo ""
	echo "from Github PR#${PR_NUM} - ${PR_TITLE}"

	# Results could be paginated. So get the link head info and find the last page number to construct the URL
	url="https://api.github.com/repos/thesofproject/linux/pulls/"$PR_NUM"/reviews"
	curl -s -I -H "Authorization: token $1" $url > info.txt
	IFS=$'\n' read -d '' -r -a info_lines < info.txt
	found_link=0
	for info_line in "${info_lines[@]}"
	do
		if [[ $info_line == *"link:"* ]]; then
			found_link=1
			break
		fi
	done

	if [[ $found_link -eq 1 ]]; then
		IFS=$',' read -d '' -r -a link_header_fields <<< $info_line
		IFS=$';' read -d '' -r -a link_header <<< ${link_header_fields[1]}
		# remove the brackets
		url=`echo "${link_header[0]:2: -1}"`
	fi

	#get emails of users who approved the PR
	#url="https://api.github.com/repos/thesofproject/linux/pulls/"$PR_NUM"/reviews"
	curl -s -H "Authorization: token $1" $url | jq -r '[.[] | select(.state=="APPROVED") | {user: .user.login}]' > users.json
	userarray=`cat users.json | jq -r '[.[] | join(",")] | @csv'`
	IFS=',' read -r -a hubuser <<< "$userarray"

	num_approvals=${#hubuser[@]}

	if [ $num_approvals == 0 ]
	then
		echo "No approvals"
		git cherry-pick $SHA >&/dev/null
		continue
	fi

	echo "Number of approvals: '$num_approvals'"

	emails=""
	fullnames=""
	for element in "${hubuser[@]}"
	do
		github_name="${element%\"}"
		github_name="${github_name#\"}"
		url="https://api.github.com/users/"$github_name
		email=`curl -s -H "Authorization: token $1" $url | jq '.email'`
		fullname=`curl -s -H "Authorization: token $1" $url | jq '.name'`

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

		github_email_fixup ${github_email} github_email

		emails="${emails},${github_email}"
		fullnames="${fullnames},${fullname}"
	done

	# just cherry-pick if there're no valid emails/full names
	if [[ -z "$emails" ]] || [[ -z $fullnames ]]
	then
		git cherry-pick $SHA >&/dev/null
		continue
	fi

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
	git cherry-pick $SHA >&/dev/null
	git rebase HEAD~1 -x 'git commit --amend -m "$(git log --format=%B -n1)$(/bin/echo -e '"$reviewed"')"' >&/dev/null
done

rm users.json
rm node.json
rm log.txt
rm commits.txt
