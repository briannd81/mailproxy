#!/bin/ksh
# Author: CDang
# Date: 7/10/14
# Purpose: send email via jump box
# usage: mailp [ options ]
#    -a               	file attachment (optional)
#    -b                 content of body or file (required)
#    -r                 from address (required)
#    -s              	subject of the email (required)
#    -t			to address (required)
#

########################################################
#                GLOBAL VARIABLES
########################################################
rem_user="xxx"
rem_ip="xxx.xxx.xxx.xxx"
ssh_opt="-o StrictHostKeyChecking=no UserKnownHostsFile=/dev/null"
rem_dir="xx"

########################################################
#			FUNCTIONS	               #	
########################################################

########################################################
# Function: usage()
# Return: void
########################################################
function usage
{
        printf "Usage: mailp \n\t%s \n\t%s \n\t%s \n\t%s \n\t%s " \
                "-a           	name or complete path of file attached (optional) " \
                "-b              content of body or file (required) " \
                "-r              from address (required)" \
                "-s          	subject of the email (required)" \
                "-t		to address (required)"
        echo
}

#######################################################
# Function: validate_arg()
# Arg: $1(param_count), $2(param_limit)
# Return: 1 if parameter exceeds limit, otherwise 0
#######################################################
function validate_arg
{
	if [[ $1 -eq $2 ]]; then
		return 0
	else
		return 1
	fi
}

#######################################################
# Function: push_file
# Desc: Copy attachment file to jump host
# Arg: $1(file_attachment)
# Return: 0 if successful, 1 if failed
#######################################################
function push_file
{
	#if sudo scp ${ssh_opt} -q "${1}" ${rem_user}@${rem_ip}:${rem_dir}/`basename ${1}`; then
	if scp -q "${1}" "${rem_user}@${rem_ip}:${rem_dir}/`basename ${1}`"; then
		return 0
	else
		return 1
	fi
}
#######################################################
# Function: del_file
# Desc: Delete attachment file from proxy
# Arg: $1(file_attachment)
# Return: 0 if successful, 1 if failed
#######################################################
function del_file
{
	#if sudo ssh ${ssh_opt} -q ${rem_user}@${rem_ip} "rm -f ${rem_dir}/`basename \"${1}\"`"; then
	if ssh -q ${rem_user}@${rem_ip} "rm -f ${rem_dir}/`basename \"${1}\"`"; then
		return 0
	else
		return 1
	fi
}
#######################################################
# Function: mailx_kickoff
# Desc: Kickoff mailx on proxy
# Arg: $1(mailx_string)
# Return: 0 if successful, 1 if failed
#######################################################
function mailx_kickoff
{
	#if sudo ssh ${ssh_opt} -q ${rem_user}@${rem_ip} "${mailx_string}"; then
	if ssh -q ${rem_user}@${rem_ip} "${mailx_string}"; then
		return 0
	else
		return 1
	fi
}
#######################################################
# Function: logging
# Desc: Print message to console, and write to mailp.log and syslog
# Arg: $1(message)
# Return: void
#######################################################
function logging
{
	echo `date +"%m-%d-%y %H:%M"     ` "${1}" | tee -a /var/log/mailp.log
	logger "${1}"
}


########################################################
#               	   MAIN                        #
########################################################
#mailx parameters
typeset from=""
typeset to=""
typeset subject=""
typeset body=""
typeset attachment=""

#parameter count
typeset -i from_count=0
typeset -i to_count=0
typeset -i subject_count=0
typeset -i body_count=0
typeset -i attachment_count=0

#set param limit to 1 of each type
typeset -i arg_limit=1

#read parameters
while getopts a:b:r:s:t:u opt
do
        case $opt in
        a)      ((attachment_count=attachment_count+1)) 
		attachment="$OPTARG";;
        b)     	((body_count=body_count+1))
		body="$OPTARG";;
        r)      ((from_count=from_count+1))
		from="$OPTARG";;
        s)      ((subject_count=subject_count+1))
                subject="$OPTARG";;
        t)      ((to_count=to_count+1))
                to="$OPTARG";;
	u)	usage
		exit 1;;
        ?)      usage
		exit 1;;
        esac
done

#validate only one count for each required parameter
if ! validate_arg "${from_count}" "${arg_limit}"; then
	logging "[-r From_Address]: parameter missing or has more than one"
	exit 1
fi
if ! validate_arg "${to_count}" "${arg_limit}"; then
	logging "[-t To_Address]: parameter missing or has more than one"
	exit 1
fi
if ! validate_arg "${subject_count}" "${arg_limit}"; then
	logging "[-s Subject]: parameter missing or has more than one"
	exit 1
fi
if ! validate_arg "${body_count}" "${arg_limit}"; then
	logging "[-b Body_File]: parameter missing or has more than one"
	exit 1
fi

#validate optional attachment parameter equals 1
if [[ ${attachment_count} -gt 1 ]]; then
	logging "[-a Attachment_File]: only one parameter of this type is allowed"
	exit 1
fi

#exit if attachment missing
if [[ ${attachment_count} -eq 1 && ! -e ${attachment} ]]; then
	logging "The attachment file \"${attachment}\" does not exists"
	exit 1
fi

#exit if body file missing
if [[ ! -e ${body} ]]; then
	logging "The body file \"${body}\" does not exists"
	exit 1
fi

#prepare mailx command
typeset mailx_string=""
if [[ -e ${attachment} ]]; then
	mailx_string="mailx -s \"${subject}\" -a \"${rem_dir}/`basename ${attachment}`\" -r \"${from}\" \"${to}\" < \"${rem_dir}/`basename ${body}`\""
else
	mailx_string="mailx -s \"${subject}\" -r \"${from}\" \"${to}\" < \"${rem_dir}/`basename ${body}`\""
fi

#push attachment
if [[ ${attachment_count} -eq 1 ]]; then
	if push_file "${attachment}"; then
		logging "push ${attachment} successful"
	else
		logging "push ${attachment} failed"
		exit 1
	fi
fi

#push body file
if push_file "${body}"; then
	logging "push ${body} successful"
else
	logging "push ${body} failed"

	#rolled back attachment
	if del_file "${attachment}"; then
		logging "roll back ${attachment} successful"
	else
		logging "roll back ${attachment} failed"
	fi

	exit 1
fi

#execute mailx remotely
if mailx_kickoff "${mailx_string}"; then
	logging "Email successfully sent from ${from} to ${to} by `id -u -l -n`"
else
	logging "Email failed to send from ${from} to ${to} by `id -u -l -n`"
fi

#give mailx few seconds to send attach file before deletion
sleep 10

#delete attachment
if [[ -e "${attachment}" ]]; then
	if del_file "${attachment}"; then
		logging "del ${attachment} successful"
	else
		logging "del ${attachment} failed"
	fi
fi

#delete body
if del_file "${body}"; then
	logging "del ${body} successful"
else
	logging "del ${body} failed"
fi
