#!/bin/bash

# This script is used by Nagios to post alerts into a Slack channel
# using the Incoming WebHooks integration. Create the channel, botname
# and integration first and then add this notification script in your
# Nagios configuration.
#
# All variables that start with NAGIOS_ are provided by Nagios as
# environment variables when an notification is generated.
# A list of the env variables is available here:
#   http://nagios.sourceforge.net/docs/3_0/macrolist.html
#
# More info on Slack
# Website: https://slack.com/
# Twitter: @slackhq, @slackapi
#
# My info
# Website: http://matthewcmcmillan.blogspot.com/
# Twitter: @matthewmcmillan
#
# Modified and adapted by DATAenligne Inc.
# Script has been modified to work with Centreon
# When configuring nagios, make sure you pass the argument within double quote ("")
# Eg: /usr/local/bin/centreon-slack.sh "$SERVICESTATE$" "$HOSTNAME$" "$SERVICEDESC$" "$HOSTOUTPUT$" "$SERVICEOUTPUT$" "$NOTIFICATIONTYPE$" "$SERVICEACKAUTHOR$" "$NOTIFICATIONNUMBER$" > /tmp/slack.log 2>&1
# Latest version: 2017
#
#Modify these variables for your environment
MY_NAGIOS_HOSTNAME="change.me.com"
SLACK_HOSTNAME="changeme.slack.com"
SLACK_TOKEN="xoxb-change-me"
SLACK_CHANNEL="#changeme"
SLACK_BOTNAME="changeme"
SLACK_HOOKS_URL="https://hooks.slack.com/services/some/url/here

#Put arguments into variables
NAGIOS_SERVICESTATE=$1
NAGIOS_HOSTNAME=$2
NAGIOS_SERVICEDISPLAYNAME=$3
NAGIOS_SERVICEOUTPUT=$4
NAGIOS_SERVICERESULT=$5
NAGIOS_NOTIFICATIONTYPE=$6
NAGIOS_ACKAUTHOR=$7
NAGIOS_NOTIFICATION_NUMBER=$8
NAGIOS_SERVICEDURATION=$9

CENTREON_URL="http://$MY_NAGIOS_HOSTNAME/centreon/main.php?p=20201&o=svcd&host_name=$NAGIOS_HOSTNAME&service_description=$NAGIOS_SERVICEDISPLAYNAME"
CENTREON_ACK_URL="http://$MY_NAGIOS_HOSTNAME/centreon/main.php?p=20201&o=svcak&cmd=15&host_name=$NAGIOS_HOSTNAME&service_description=$NAGIOS_SERVICEDISPLAYNAME&en=1"

if [ "$NAGIOS_NOTIFICATIONTYPE" = "ACKNOWLEDGEMENT" ]
then
        ICON=":thumbsup:"
        curl -X POST --data-urlencode "payload={\"channel\": \"${SLACK_CHANNEL}\", \"username\": \"${SLACK_USERNAME}\", \"text\": \"============================================================== \n*STATUS:* ${ICON} (${NAGIOS_NOTIFICATIONTYPE}) \n*ACKNOWLEDGE AUTHOR:* $NAGIOS_ACKAUTHOR \n*HOST:* ${NAGIOS_HOSTNAME} \n*SERVICE:* ${NAGIOS_SERVICEDISPLAYNAME} \n *SERVICE OUTPUT:* ${NAGIOS_SERVICERESULT} \n*SERVICE URL:* <$CENTREON_URL|See Nagios...>\n============================================================== \n\"}"  $SLACK_HOOKS_URL
else

        #Set the message icon based on Nagios service state
        if [ "$NAGIOS_SERVICESTATE" = "CRITICAL" ]
        then
            ICON=":exclamation:"
            STATUT="CRITICAL"
        elif [ "$NAGIOS_SERVICESTATE" = "WARNING" ]
        then
            ICON=":warning:"
            STATUT="WARNING"
        elif [ "$NAGIOS_SERVICESTATE" = "OK" ]
        then
            ICON=":white_check_mark:"
            STATUT="OK"
        elif [ "$NAGIOS_SERVICESTATE" = "UNKNOWN" ]
        then
            ICON=":question:"
            STATUT="UNKNOWN"
        else
            ICON=":white_medium_square:"
            STATUT="NA"
        fi

        #Send message to Slack
        curl -X POST --data-urlencode "payload={\"channel\": \"${SLACK_CHANNEL}\", \"username\": \"${SLACK_USERNAME}\", \"text\": \"============================================================== \n*STATUS:* ${ICON} (${STATUT})\n*DOWN DURATION:* ${NAGIOS_SERVICEDURATION} \n*NOTIFICATION NUMBER:* ${NAGIOS_NOTIFICATION_NUMBER}  \n*HOST:* ${NAGIOS_HOSTNAME} \n*SERVICE:* ${NAGIOS_SERVICEDISPLAYNAME} \n *SERVICE OUTPUT:* ${NAGIOS_SERVICERESULT} \n *ACKNOWLEDGE SERVICE:* <$CENTREON_ACK_URL|Acknowledge Service...> \n*SERVICE URL:* <$CENTREON_URL|See Nagios...>\n============================================================== \n\"}" $SLACK_HOOKS_URL
fi
