#!/bin/bash

# Invocation:
# fetch-xml.sh RemoteURL LocalFile ErrorsTo [SigningCert]
#
# Download XML file from remote URL into LocalFile, optionally verify with
# SigningCertificate and report any errors by email to ErrorsTo
#
# Environment variables:
#
#   XMLSECTOOL: path to XmlSEcTool executable to use for signature validation
#       (defaults to first instance found in path with `which xmlsectool)
#   WGET_OPTS: optional arguments to pass to wget.  To allow passing spaces in options
#       (for extra HTTP headers), multiple options must be separated with \t.
#
# External dependencies:
#    xmllint: for checking XML well-formedness
#    wget: for downloading the remote URL
#    mail: for sending mail
#        (all these three are part of standard install on most Linux systems)
#    xmlsectool (optional, for signature checking).
#      * Follow https://wiki.shibboleth.net/confluence/display/SHIB2/XmlSecTool for installation
#      * Either add the xmlsectool directory to PATH or set XMLSECTOOL variable to the xmlsectool binary
#
# The SigningCertificate is optional - only if it is specified, the signature
# on the downloaded file would be verified.  And in that case, if xmlsectool
# cannot be found, the program would fail.
# 
# For security reasons, if not doing signature checking, it is highly important
# to be downloading the files over https - which protects the integrity well.

if [ $# -lt 2 -o $# -gt 4 ] ; then 
  echo "ERROR: Invalid number of arguments"
  echo "Usage:"
  echo "    $0 RemoteURL LocalFile ErrorsTo [SigningCert]"
  exit 1
fi

REMOTE_URL="$1"
LOCAL_FILE="$2"
LOCAL_TMP_FILE="$2.new.$$"
ERRORS_TO="${3:-}" # leave blank if no argument passed
LOGFILE=`mktemp`
SIGNING_CERT=${4:-} # leave blank if no argument passed

XMLSECTOOL=${XMLSECTOOL:-`which xmlsectool 2> /dev/null`}

{ echo "fetch-xml.sh starting: `date`" 
echo "Invoked as: $0 $*"
echo "REMOTE_URL=$REMOTE_URL"
echo "LOCAL_FILE=$LOCAL_FILE"
echo "LOCAL_TMP_FILE=$LOCAL_TMP_FILE"
echo "ERRORS_TO=$ERRORS_TO"
echo "SIGNING_CERT=$SIGNING_CERT"
echo "XMLSECTOOL=$XMLSECTOOL"
echo "WGET_OPTS=$WGET_OPTS"
} >> $LOGFILE

function BailOut {
  if [ -n "$ERRORS_TO" ] ; then
      mail -s "fetch failed: $1" $ERRORS_TO < $LOGFILE
  fi
  rm $LOGFILE
  # note: we may be leaving the temporary download file behind - intentionally,
  # so that it can be used to troubelshoot what went wrong.
  exit 1
}

# Sanity check:
if [ -n "$SIGNING_CERT" -a -z "$XMLSECTOOL" ] ; then
    BailOut "Sanity check: signing certificate specified but xmlsectool not found"
fi

# Step 1: download the file
# Temporarily set IFS to jut \t for WGET_OPTS handling
( IFS=$'\t' ; wget $WGET_OPTS -O $LOCAL_TMP_FILE $REMOTE_URL >> $LOGFILE 2>&1 )
if [ $? -ne 0 ] ; then BailOut "wget $REMOTE_URL failed"; fi

# Step 2: check the file is well-formed
xmllint -noout $LOCAL_TMP_FILE >> $LOGFILE 2>&1
if [ $? -ne 0 ] ; then BailOut "xmllint $LOCAL_TMP_FILE failed"; fi

# Skip schema validation - it would be too much hassle to setup schema files at
# each client site, and schema validation is done before signing the file at
# distribution site.  
# So any file that passes signature check is also schema valid.

if [ -n "$SIGNING_CERT" ] ; then
    $XMLSECTOOL --verifySignature --inFile $LOCAL_TMP_FILE --certificate $SIGNING_CERT >> $LOGFILE 2>&1
    if [ $? -ne 0 ] ; then BailOut "signature verification failed"; fi
fi

# We are all good.  One final check: if the source and destination files are the same, quietly stop
diff $LOCAL_TMP_FILE $LOCAL_FILE > /dev/null 2>> $LOGFILE
if [ $? -eq 0 ] ; then 
   # no differences
   rm $LOCAL_TMP_FILE
else
   # Create a backup copy of the target file.
   # Check the file exists - so that we do not report an error on the first
   # invocation.
   if [ -e $LOCAL_FILE ] ; then cp -f -p $LOCAL_FILE $LOCAL_FILE.bak ; fi

   # Move the new file into the target location
   mv -f $LOCAL_TMP_FILE $LOCAL_FILE
   # Touch the file to make the timestamp current - workaround an OpenSAML2 bug.
   # See https://issues.shibboleth.net/jira/browse/OSJ-165 for more info
   touch $LOCAL_FILE
fi

# all good - remove log file
rm -f $LOGFILE

