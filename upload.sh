[ -f .config ] && . .config

FTP_HOST=${FTP_HOST:-'updatethis'}
FTP_USER=${FTP_USER:-'remoteusername'}
FTP_PASS=${FTP_PASS:-'remotepasswd'}
FTP_FILE=${FTP_FILE:-'my-net-installer.iso'}
FTP_UPLOAD_DIR=${FTP_UPLOAD_DIR:-'/cdrom'}

_FILE=$(basename ${FTP_FILE})
_DIR=$(dirname ${FTP_FILE})

pushd $_DIR

ftp -n -v $FTP_HOST << EOT
ascii
user $FTP_USER $FTP_PASS
prompt
cd ${FTP_UPLOAD_DIR}
ls -la
binary
put ${_FILE}
bye
EOT

popd
