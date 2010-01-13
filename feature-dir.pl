# Functions for managing a domain's home directory

# setup_dir(&domain)
# Creates the home directory
sub setup_dir
{
local $tmpl = &get_template($_[0]->{'template'});
&require_useradmin();
local $qh = quotemeta($_[0]->{'home'});
&$first_print($text{'setup_home'});

# Get Unix user, either for this domain or its parent
local $uinfo;
if ($_[0]->{'unix'} || $_[0]->{'parent'}) {
	local @users = &list_all_users();
	($uinfo) = grep { $_->{'user'} eq $_[0]->{'user'} } @users;
	}
if ($_[0]->{'unix'} && !$uinfo) {
	# If we are going to have a Unix user but none has been created
	# yet, fake his details here for use in chowning and skel copying
	# This should never happen!
	$uinfo ||= { 'uid' => $_[0]->{'uid'},
		     'gid' => $_[0]->{'ugid'},
		     'shell' => '/bin/sh',
		     'group' => $_[0]->{'group'} || $_[0]->{'ugroup'} };
	}

# Create and populate home directory
local $perms = oct($uconfig{'homedir_perms'});
if (&has_domain_user($_[0]) && $_[0]->{'parent'}) {
	# Run as domain owner, as this is a sub-server
	&make_dir_as_domain_user($_[0], $_[0]->{'home'}, $perms);
	&set_permissions_as_domain_user($_[0], $perms, $_[0]->{'home'});
	}
else {
	# Run commands as root, as user is missing
	if (!-d $_[0]->{'home'}) {
		&make_dir($_[0]->{'home'}, $perms);
		}
	&set_ownership_permissions(undef, undef, $perms, $_[0]->{'home'});
	if ($uinfo) {
		&set_ownership_permissions($uinfo->{'uid'}, $uinfo->{'gid'},
					   undef, $_[0]->{'home'});
		}
	}

# Populate home dir
if ($tmpl->{'skel'} ne "none" && !$_[0]->{'nocopyskel'} &&
    !$_[0]->{'alias'}) {
	&copy_skel_files(&substitute_domain_template($tmpl->{'skel'}, $_[0]),
			 $uinfo, $_[0]->{'home'},
			 $_[0]->{'group'} || $_[0]->{'ugroup'}, $_[0]);
	}

# If this is a sub-domain, move public_html from any skeleton to it's sub-dir
# under the parent
if ($_[0]->{'subdom'}) {
	local $phsrc = &public_html_dir($_[0], 0, 1);
	local $phdst = &public_html_dir($_[0], 0, 0);
	if (-d $phsrc && !-d $phdst) {
		&make_dir($phdst, 0755);
		&set_ownership_permissions($_[0]->{'uid'}, $_[0]->{'gid'},
					   undef, $phdst);
		&copy_source_dest($phsrc, $phdst);
		&unlink_file($phsrc);
		}
	}

# Setup sub-directories
&create_standard_directories($_[0]);
&$second_print($text{'setup_done'});

# Create mail file
if (!$_[0]->{'parent'}) {
	&$first_print($text{'setup_usermail3'});
	eval {
		local $main::error_must_die = 1;
		&create_mail_file(\%uinfo);

		# Set the user's Usermin IMAP password
		&set_usermin_imap_password($uinfo);
		};
	if ($@) {
		&$second_print(&text('setup_eusermail3', "$@"));
		}
	else {
		&$second_print($text{'setup_done'});
		}
	}

return 1;
}

# create_standard_directories(&domain)
# Create and set permissions on standard directories
sub create_standard_directories
{
local ($d) = @_;
foreach my $dir (&virtual_server_directories($d)) {
	local $path = "$d->{'home'}/$dir->[0]";
	&lock_file($path);
	if (&has_domain_user($d)) {
		# Do creation as domain owner
		if (!-d $path) {
			&make_dir_as_domain_user($d, $path, oct($dir->[1]), 1);
			}
		&set_permissions_as_domain_user($d, oct($dir->[1]), $path);
		}
	else {
		# Need to run as root
		if (!-d $path) {
			&make_dir($path, oct($dir->[1]), 1);
			}
		&set_ownership_permissions(undef, undef, oct($dir->[1]), $path);
		if ($d->{'uid'} && ($d->{'unix'} || $d->{'parent'})) {
			&set_ownership_permissions($d->{'uid'}, $d->{'gid'},
						   undef, $path);
			}
		}
	&unlock_file($path);
        }
}

# modify_dir(&domain, &olddomain)
# Rename home directory if needed
sub modify_dir
{
# Special case .. converting alias to non-alias, so some directories need to
# be created
if ($_[1]->{'alias'} && !$_[0]->{'alias'}) {
	&$first_print($text{'save_dirunalias'});
	local $tmpl = &get_template($_[0]->{'template'});
	if ($tmpl->{'skel'} ne "none") {
		local $uinfo = &get_domain_owner($_[0], 1);
		&copy_skel_files(
			&substitute_domain_template($tmpl->{'skel'}, $_[0]),
			$uinfo, $_[0]->{'home'},
			$_[0]->{'group'} || $_[0]->{'ugroup'}, $_[0]);
		}
	&create_standard_directories($_[0]);
	&$second_print($text{'setup_done'});
	}

if (defined(&set_php_wrappers_writable)) {
	&set_php_wrappers_writable($_[1], 1);
	}
if ($_[0]->{'home'} ne $_[1]->{'home'}) {
	# Move the home directory if changed, and if not already moved as
	# part of parent
	if (-d $_[1]->{'home'}) {
		&$first_print($text{'save_dirhome'});
		if (defined(&set_php_wrappers_writable)) {
			&set_php_wrappers_writable($_[0], 1);
			}
		local $cmd = $config{'move_command'} || "mv";
		$cmd .= " ".quotemeta($_[1]->{'home'}).
			" ".quotemeta($_[0]->{'home'});
		$cmd .= " 2>&1 </dev/null";
		&set_domain_envs($_[1], "MODIFY_DOMAIN", $_[0]);
		local $out = &backquote_logged($cmd);
		&reset_domain_envs($_[1]);
		if ($?) {
			&$second_print(&text('save_dirhomefailed', "<tt>$out</tt>"));
			}
		else {
			&$second_print($text{'setup_done'});
			}
		if (defined(&set_php_wrappers_writable)) {
			&set_php_wrappers_writable($_[0], 0);
			}
		}
	}
if ($_[0]->{'unix'} && !$_[1]->{'unix'} ||
    $_[0]->{'uid'} ne $_[1]->{'uid'}) {
	# Unix user now exists or has changed! Set ownership of home dir
	&$first_print($text{'save_dirchown'});
	&set_home_ownership($_[0]);
	&$second_print($text{'setup_done'});
	}
if (!$_[0]->{'subdom'} && $_[1]->{'subdom'}) {
	# No longer a sub-domain .. move the HTML dir
	local $phsrc = &public_html_dir($_[1]);
	local $phdst = &public_html_dir($_[0]);
	&copy_source_dest($phsrc, $phdst);
	&unlink_file($phsrc);

	# And the CGI directory
	local $cgisrc = &cgi_bin_dir($_[1]);
	local $cgidst = &cgi_bin_dir($_[0]);
	&copy_source_dest($cgisrc, $cgidst);
	&unlink_file($cgisrc);
	}
if (defined(&set_php_wrappers_writable)) {
	&set_php_wrappers_writable($_[0], 0);
	}
}

# delete_dir(&domain)
# Delete the home directory
sub delete_dir
{
# Delete homedir
if (-d $_[0]->{'home'} && $_[0]->{'home'} ne "/") {
	&$first_print($text{'delete_home'});
	if (defined(&set_php_wrappers_writable)) {
		&set_php_wrappers_writable($_[0], 1);
		}
	local $err = &backquote_logged("rm -rf ".quotemeta($_[0]->{'home'}).
				       " 2>&1");
	if ($?) {
		# Try again after running chattr
		if (&has_command("chattr")) {
			&system_logged("chattr -i -R ".
				       quotemeta($_[0]->{'home'}));
			$err = &backquote_logged(
				"rm -rf ".quotemeta($_[0]->{'home'})." 2>&1");
			$err = undef if (!$?);
			}
		}
	else {
		$err = undef;
		}
	if ($err) {
		# Ignore an error deleting a mount point
		local @subs = &sub_mount_points($_[0]->{'home'});
		if (@subs) {
			$err = undef;
			}
		}
	if ($err) {
		&$second_print(&text('delete_ehome', &html_escape($err)));
		}
	else {
		&$second_print($text{'setup_done'});
		}
	}
}

# validate_dir(&domain)
# Returns an error message if the directory is missing, or has the wrong
# ownership
sub validate_dir
{
local ($d) = @_;
if (!-d $d->{'home'}) {
	return &text('validate_edir', "<tt>$d->{'home'}</tt>");
	}
local @st = stat($d->{'home'});
if ($d->{'uid'} && $st[4] != $d->{'uid'}) {
	local $owner = getpwuid($st[4]);
	return &text('validate_ediruser', "<tt>$d->{'home'}</tt>",
		     $owner, $d->{'user'})
	}
if ($d->{'gid'} && $st[5] != $d->{'gid'} && $st[5] != $d->{'ugid'}) {
	local $owner = getgrgid($st[5]);
	return &text('validate_edirgroup', "<tt>$d->{'home'}</tt>",
		     $owner, $d->{'group'})
	}
foreach my $sd (&virtual_server_directories($d)) {
	if (!-d "$d->{'home'}/$sd->[0]") {
		return &text('validate_esubdir', "<tt>$sd->[0]</tt>")
		}
	local @st = stat("$d->{'home'}/$sd->[0]");
	if ($d->{'uid'} && $st[4] != $d->{'uid'}) {
		local $owner = getpwuid($st[4]);
		return &text('validate_esubdiruser', "<tt>$sd->[0]</tt>",
			     $owner, $d->{'user'})
		}
	if ($d->{'gid'} && $st[5] != $d->{'gid'} && $st[5] != $d->{'ugid'}) {
		local $owner = getgrgid($st[5]);
		return &text('validate_esubdirgroup', "<tt>$sd->[0]</tt>",
			     $owner, $d->{'group'})
		}
	}
return undef;
}

# check_dir_clash(&domain, [field])
sub check_dir_clash
{
# Does nothing ..?
return 0;
}

# backup_dir(&domain, file, &options, home-format, incremental, [&as-domain])
# Backs up the server's home directory in tar format to the given file
sub backup_dir
{
&$first_print($_[3] && $config{'compression'} == 3 ? $text{'backup_dirzip'} :
	      $_[4] ?  $text{'backup_dirtarinc'} : $text{'backup_dirtar'});
local $out;
local $cmd;
local $gzip = $_[3] && &has_command("gzip");
local $tar = &get_tar_command(); 

# Create exclude file
$xtemp = &transname();
&open_tempfile(XTEMP, ">$xtemp");
&print_tempfile(XTEMP, "domains\n");
&print_tempfile(XTEMP, "./domains\n");
if ($_[2]->{'dirnologs'}) {
	&print_tempfile(XTEMP, "logs\n");
	&print_tempfile(XTEMP, "./logs\n");
	}
&print_tempfile(XTEMP, "virtualmin-backup\n");
&print_tempfile(XTEMP, "./virtualmin-backup\n");
foreach my $e (&get_backup_excludes($_[0])) {
	&print_tempfile(XTEMP, "$e\n");
	&print_tempfile(XTEMP, "./$e\n");
	}

# Exclude all .zfs files, for Solaris
if ($gconfig{'os_type'} eq 'solaris') {
	open(FIND, "find ".quotemeta($_[0]->{'home'})." -name .zfs |");
	while(<FIND>) {
		s/\r|\n//g;
		s/^\Q$_[0]->{'home'}\E\///;
		&print_tempfile(XTEMP, "$_\n");
		&print_tempfile(XTEMP, "./$_\n");
		}
	close(FIND);
	}
&close_tempfile(XTEMP);

# Work out incremental flags
local ($iargs, $iflag, $ifile, $ifilecopy);
if (&has_incremental_tar()) {
	if (!-d $incremental_backups_dir) {
		&make_dir($incremental_backups_dir, 0700);
		}
	$ifile = "$incremental_backups_dir/$_[0]->{'id'}";
	if (!$_[4]) {
		# Force full backup
		&unlink_file($ifile);
		}
	else {
		# Add a flag file indicating that this was an incremental,
		# and take a copy of the file so we can put it back as before
		# the backup (as tar modifies it)
		if (-r $ifile) {
			$iflag = "$_[0]->{'home'}/.incremental";
			&open_tempfile(IFLAG, ">$iflag", 0, 1);
			&close_tempfile(IFLAG);
			$ifilecopy = &transname();
			&copy_source_dest($ifile, $ifilecopy);
			}
		}
	$iargs = "--listed-incremental=$ifile";
	}

# Create the writer command. This will be run as the domain owner if this
# is the final step of the backup process, and if the owner is doing the backup.
local $writer = "cat >".quotemeta($_[1]);
if ($_[5] && $_[3]) {
	$writer = &command_as_user($_[5]->{'user'}, 0, $writer);
	}

# Do the backup
if ($_[3] && $config{'compression'} == 0) {
	# With gzip
	$cmd = "$tar cfX - $xtemp $iargs . | gzip -c $config{'zip_args'}";
	}
elsif ($_[3] && $config{'compression'} == 1) {
	# With bzip
	$cmd = "$tar cfX - $xtemp $iargs . | bzip2 -c $config{'zip_args'}";
	}
elsif ($_[3] && $config{'compression'} == 3) {
	# ZIP archive
	$cmd = "zip -r -x\@$xtemp - .";
	}
else {
	# Plain tar
	$cmd = "$tar cfX - $xtemp $iargs .";
	}
$cmd .= " | $writer";
local $ex = &execute_command("cd ".quotemeta($_[0]->{'home'})." && $cmd",
			     undef, \$out, \$out);
&unlink_file($iflag) if ($iflag);
&copy_source_dest($ifilecopy, $ifile) if ($ifilecopy);
if (-r $ifile) {
	# Make owned by domain owner, so tar can read in future
	&set_ownership_permissions($_[0]->{'uid'}, $_[0]->{'gid'},
				   0700, $ifile);
	}
if ($ex) {
	&$second_print(&text($cmd =~ /^\S*zip/ ? 'backup_dirzipfailed'
					       : 'backup_dirtarfailed',
			     "<pre>".&html_escape($out)."</pre>"));
	return 0;
	}
else {
	&$second_print($text{'setup_done'});
	return 1;
	}
}

# show_backup_dir(&options)
# Returns HTML for the backup logs option
sub show_backup_dir
{
return sprintf
	"(<input type=checkbox name=dir_logs value=1 %s> %s)",
	!$opts{'dirnologs'} ? "checked" : "", $text{'backup_dirlogs'};
}

# parse_backup_dir(&in)
# Parses the inputs for directory backup options
sub parse_backup_dir
{
local %in = %{$_[0]};
return { 'dirnologs' => !$in{'dir_logs'} };
}

# restore_dir(&domain, file, &options, homeformat?, &oldd, asowner)
# Extracts the given tar file into server's home directory
sub restore_dir
{
&$first_print($text{'restore_dirtar'});
local $tar = &get_tar_command(); 
local $iflag = "$_[0]->{'home'}/.incremental";
&unlink_file($iflag);
if (defined(&set_php_wrappers_writable)) {
	&set_php_wrappers_writable($_[0], 1, 1);
	}

# Create exclude file, to skip local system-specific files
local $xtemp = &transname();
&open_tempfile(XTEMP, ">$xtemp");
&print_tempfile(XTEMP, "cgi-bin/lang\n");	# Used by AWstats, and created
&print_tempfile(XTEMP, "./cgi-bin/lang\n");	# locally .. so no need to
&print_tempfile(XTEMP, "cgi-bin/lib\n");	# include in restore.
&print_tempfile(XTEMP, "./cgi-bin/lib\n");
&print_tempfile(XTEMP, "cgi-bin/plugins\n");
&print_tempfile(XTEMP, "./cgi-bin/plugins\n");
&print_tempfile(XTEMP, "public_html/icon\n");
&print_tempfile(XTEMP, "./public_html/icon\n");
&print_tempfile(XTEMP, "public_html/awstats-icon\n");
&print_tempfile(XTEMP, "./public_html/awstats-icon\n");
&close_tempfile(XTEMP);

# Check if Apache logs were links before the restore
local $alog = "$_[0]->{'home'}/logs/access_log";
local $elog = "$_[0]->{'home'}/logs/error_log";
local ($aloglink, $eloglink);
if ($_[0]->{'web'}) {
	$aloglink = readlink($alog);
	$eloglink = readlink($elog);
	}

local $out;
local $cf = &compression_format($_[1]);
local $q = quotemeta($_[1]);
local $qh = quotemeta($_[0]->{'home'});
if ($cf == 4) {
	# Unzip command does un-compression and un-archiving
	# XXX ZIP doesn't support excludes of paths :-(
	&execute_command("cd $qh && unzip -o $q", undef, \$out, \$out);
	}
else {
	local $comp = $cf == 1 ? "gunzip -c" :
		      $cf == 2 ? "uncompress -c" :
		      $cf == 3 ? "bunzip2 -c" : "cat";
	local $tarcmd = "$tar xfX - $xtemp";
	#if ($_[6]) {
	#	# Run as domain owner - disabled, as this prevents some files
	#	# from being written to by tar
	#	$tarcmd = &command_as_user($_[0]->{'user'}, 0, $tarcmd);
	#	}
	&execute_command("cd $qh && $comp $q | $tarcmd", undef, \$out, \$out);
	}
if ($?) {
	# Errors about utime in the tar extract are ignored when running
	# as the domain owner
	&$second_print(&text('backup_dirtarfailed', "<pre>$out</pre>"));
	return 0;
	}
else {
	# Check for incremental restore of new-created domain, which indicates
	# that is is not complete
	if ($_[0]->{'wasmissing'} && -r $iflag) {
		&$second_print($text{'restore_wasmissing'});
		}
	else {
		&$second_print($text{'setup_done'});
		}
	&unlink_file($iflag);

	if ($_[0]->{'unix'}) {
		# Set ownership on extracted home directory, apart from
		# content of ~/homes - unless running as the domain owner,
		# in which case ~/homes is set too
		&$first_print($text{'restore_dirchowning'});
		&set_home_ownership($_[0]);
		if ($_[6]) {
			&set_mailbox_homes_ownership($_[0]);
			}
		&$second_print($text{'setup_done'});
		}
	if (defined(&set_php_wrappers_writable)) {
		&set_php_wrappers_writable($_[0], 0, 1);
		}
	
	# Incremental file is no longer valid, so clear it
	local $ifile = "$incremental_backups_dir/$_[0]->{'id'}";
	&unlink_file($ifile);

	# Check if logs are links now .. if not, we need to move the files
	local $new_aloglink = readlink($alog);
	local $new_eloglink = readlink($elog);
	if ($_[0]->{'web'} && !$_[0]->{'subdom'} && !$_[0]->{'alias'}) {
		local $new_alog = &get_apache_log(
			$_[0]->{'dom'}, $_[0]->{'web_port'}, 0);
		local $new_elog = &get_apache_log(
			$_[0]->{'dom'}, $_[0]->{'web_port'}, 1);
		if ($aloglink && !$new_aloglink) {
			&system_logged("mv ".quotemeta($alog)." ".
					     quotemeta($new_alog));
			}
		if ($eloglink && !$new_eloglink) {
			&system_logged("mv ".quotemeta($elog)." ".
					     quotemeta($new_elog));
			}
		}

	return 1;
	}
}

# set_home_ownership(&domain)
# Update the ownership of all files in a server's home directory, EXCEPT
# the homes directory which is used by mail users
sub set_home_ownership
{
local ($d) = @_;
local $hd = $config{'homes_dir'};
$hd =~ s/^\.\///;
local $gid = $d->{'gid'} || $d->{'ugid'};
if (defined(&set_php_wrappers_writable)) {
	&set_php_wrappers_writable($d, 1);
	}
&system_logged("find ".quotemeta($d->{'home'})." ! -type l ".
	       " | grep -v ".quotemeta("$d->{'home'}/$hd/").
	       " | sed -e 's/^/\"/' | sed -e 's/\$/\"/' ".
	       " | xargs chown $d->{'uid'}:$gid");
&system_logged("chown $d->{'uid'}:$gid ".
	       quotemeta($d->{'home'})."/".$config{'homes_dir'});
if (defined(&set_php_wrappers_writable)) {
	&set_php_wrappers_writable($d, 0);
	}
}

# set_mailbox_homes_ownership(&domain)
# Set the owners of all directories under ~/homes to their mailbox users
sub set_mailbox_homes_ownership
{
local ($d) = @_;
local $hd = $config{'homes_dir'};
$hd =~ s/^\.\///;
local $homes = "$d->{'home'}/$hd";
foreach my $user (&list_domain_users($d, 1, 1, 1, 1)) {
	if (&is_under_directory($homes, $user->{'home'}) &&
	    !$user->{'webowner'} && $user->{'home'}) {
		&system_logged("find ".quotemeta($user->{'home'}).
			       " | sed -e 's/^/\"/' | sed -e 's/\$/\"/' ".
			       " | xargs chown $user->{'uid'}:$user->{'gid'}");
		}
	}
}

# virtual_server_directories(&dom)
# Returns a list of sub-directories that need to be created for virtual servers
sub virtual_server_directories
{
local ($d) = @_;
local $tmpl = &get_template($d->{'template'});
local $perms = $tmpl->{'web_html_perms'};
return ( $d->{'subdom'} || $d->{'alias'} ? ( ) :
		( [ &public_html_dir($d, 1), $perms ] ),
         $d->{'subdom'} || $d->{'alias'} ? ( ) :
		( [ &cgi_bin_dir($d, 1), $perms ] ),
         [ 'logs', '750' ],
         [ $config{'homes_dir'}, '755' ] );
}

# create_server_tmp(&domain)
# Creates the temporary files directory for a domain, and returns the path
sub create_server_tmp
{
local ($d) = @_;
if ($d->{'dir'}) {
	local $tmp = "$d->{'home'}/tmp";
	if (!-d $tmp) {
		&make_dir_as_domain_user($d, $tmp, 0750, 1);
		}
	return $tmp;
	}
else {
	# For domains without a home
	return "/tmp";
	}
}

# show_template_dir(&tmpl)
# Outputs HTML for editing directory-related template options
sub show_template_dir
{
local ($tmpl) = @_;

# The skeleton files directory
print &ui_table_row(&hlink($text{'tmpl_skel'}, "template_skel"),
	&none_def_input("skel", $tmpl->{'skel'}, $text{'tmpl_skeldir'}, 0,
			$tmpl->{'standard'} ? 1 : 0, undef,
			[ "skel", "skel_subs" ])."\n".
	&ui_textbox("skel", $tmpl->{'skel'} eq "none" ? undef
						      : $tmpl->{'skel'}, 40));

# Perform substitions on skel file contents
print &ui_table_row(&hlink($text{'tmpl_skel_subs'}, "template_skel_subs"),
	&ui_yesno_radio("skel_subs", int($tmpl->{'skel_subs'})));
}

# parse_template_dir(&tmpl)
# Updates directory-related template options from %in
sub parse_template_dir
{
local ($tmpl) = @_;

# Save skeleton directory
$tmpl->{'skel'} = &parse_none_def("skel");
if ($in{"skel_mode"} == 2) {
	-d $in{'skel'} || &error($text{'tmpl_eskel'});
	$tmpl->{'skel_subs'} = $in{'skel_subs'};
	}
}

$done_feature_script{'dir'} = 1;

1;

