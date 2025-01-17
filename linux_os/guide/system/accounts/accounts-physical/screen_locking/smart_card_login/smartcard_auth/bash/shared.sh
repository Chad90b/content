# platform = Red Hat Enterprise Linux 7,Oracle Linux 7

# Install required packages
{{{ bash_package_install("esc") }}}
{{{ bash_package_install("pam_pkcs11") }}}

# Enable pcscd.socket systemd activation socket
{{{ bash_service_command("enable", "pcscd.socket") }}}

# Configure the expected /etc/pam.d/system-auth{,-ac} settings directly
#
# The code below will configure system authentication in the way smart card
# logins will be enabled, but also user login(s) via other method to be allowed
#
# NOTE: It is not possible to use the 'authconfig' command to perform the
#       remediation for us, because call of 'authconfig' would discard changes
#       for other remediations (see RH BZ#1357019 for details)
#
#	Therefore we need to configure the necessary settings directly.
#

# Define system-auth config location
SYSTEM_AUTH_CONF="/etc/pam.d/system-auth"
# Define expected 'pam_env.so' row in $SYSTEM_AUTH_CONF
PAM_ENV_SO="auth.*required.*pam_env.so"
PAM_FAIL_DELAY="auth.*required.*pam_faildelay.so"

# Define 'pam_succeed_if.so' row to be appended past $PAM_ENV_SO row into $SYSTEM_AUTH_CONF
SYSTEM_AUTH_PAM_SUCCEED="\
auth        [success=1 default=ignore] pam_succeed_if.so service notin \
login:gdm:xdm:kdm:xscreensaver:gnome-screensaver:kscreensaver quiet use_uid"
# Define 'pam_pkcs11.so' row to be appended past $SYSTEM_AUTH_PAM_SUCCEED
# row into SYSTEM_AUTH_CONF file
SYSTEM_AUTH_PAM_PKCS11="\
auth        [success=done authinfo_unavail=ignore ignore=ignore default=die] \
pam_pkcs11.so nodebug"

# Define smartcard-auth config location
SMARTCARD_AUTH_CONF="/etc/pam.d/smartcard-auth"
# Define 'pam_pkcs11.so' auth section to be appended past $PAM_ENV_SO into $SMARTCARD_AUTH_CONF
SMARTCARD_AUTH_SECTION="auth        [success=done ignore=ignore default=die] pam_pkcs11.so nodebug wait_for_card"
# Define expected 'pam_permit.so' row in $SMARTCARD_AUTH_CONF
PAM_PERMIT_SO="account.*required.*pam_permit.so"
# Define 'pam_pkcs11.so' password section
SMARTCARD_PASSWORD_SECTION="password    required      pam_pkcs11.so"

# First Correct the SYSTEM_AUTH_CONF configuration
if ! grep -q 'pam_pkcs11.so' "$SYSTEM_AUTH_CONF"
then
    # Append pam_succeed_if.so row after pam_env.so or after pam_faildelay.so when it exists.
    # Then append pam_pkcs11.so row right after the pam_succeed_if.so we just added
    # in SYSTEM_AUTH_CONF file
    # This will preserve any other already existing row equal to "$SYSTEM_AUTH_PAM_SUCCEED"
    if ! grep -q 'pam_faildelay.so' "$SYSTEM_AUTH_CONF"
    then
        echo "$(awk '/^'"$PAM_ENV_SO"'/{print $0 RS "'"$SYSTEM_AUTH_PAM_SUCCEED"'" RS "'"$SYSTEM_AUTH_PAM_PKCS11"'";next}1' "$SYSTEM_AUTH_CONF")" > "$SYSTEM_AUTH_CONF"
    else
        echo "$(awk '/^'"$PAM_FAIL_DELAY"'/{print $0 RS "'"$SYSTEM_AUTH_PAM_SUCCEED"'" RS "'"$SYSTEM_AUTH_PAM_PKCS11"'";next}1' "$SYSTEM_AUTH_CONF")" > "$SYSTEM_AUTH_CONF"
    fi

fi

# Then also correct the SMARTCARD_AUTH_CONF
if ! grep -q 'auth.*pam_pkcs11.so' "$SMARTCARD_AUTH_CONF"
then
	# Append (expected) SMARTCARD_AUTH_SECTION row past the pam_env.so into SMARTCARD_AUTH_CONF file
	sed -i --follow-symlinks -e '/^'"$PAM_ENV_SO"'/a \
        '"$SMARTCARD_AUTH_SECTION" "$SMARTCARD_AUTH_CONF"
else
    if ! grep -q 'auth.*pam_pkcs11.so.*no_debug.*wait_for_card' "$SMARTCARD_AUTH_CONF"
    then
        sed -i --follow-symlinks -e 's/^auth.*pam_pkcs11.so.*/'"$SMARTCARD_AUTH_SECTION"'/' "$SMARTCARD_AUTH_CONF"
    fi
fi
if ! grep -q 'password.*pam_pkcs11.so' "$SMARTCARD_AUTH_CONF"
then
	# Append (expected) SMARTCARD_PASSWORD_SECTION row past the pam_permit.so into SMARTCARD_AUTH_CONF file
	sed -i --follow-symlinks -e '/^'"$PAM_PERMIT_SO"'/a \
        '"$SMARTCARD_PASSWORD_SECTION" "$SMARTCARD_AUTH_CONF"
else
    if ! grep -q 'password.*required.*pam_pkcs11.so' "$SMARTCARD_AUTH_CONF"
    then
        sed -i --follow-symlinks -e 's/password.*pam_pkcs11.so.*/'"$SMARTCARD_PASSWORD_SECTION"'/' "$SMARTCARD_AUTH_CONF"
    fi
fi

# Perform /etc/pam_pkcs11/pam_pkcs11.conf settings below
# Define selected constants for later reuse
SP="[:space:]"
PAM_PKCS11_CONF="/etc/pam_pkcs11/pam_pkcs11.conf"

# Ensure OCSP is turned on in $PAM_PKCS11_CONF
# 1) First replace any occurrence of 'none' value of 'cert_policy' key setting with the correct configuration
sed -i "s/^[$SP]*cert_policy[$SP]\+=[$SP]\+none;/\t\tcert_policy = ca, ocsp_on, signature;/g" "$PAM_PKCS11_CONF"
# 2) Then append 'ocsp_on' value setting to each 'cert_policy' key in $PAM_PKCS11_CONF configuration line,
# which does not contain it yet
sed -i "/ocsp_on/! s/^[$SP]*cert_policy[$SP]\+=[$SP]\+\(.*\);/\t\tcert_policy = \1, ocsp_on;/" "$PAM_PKCS11_CONF"
