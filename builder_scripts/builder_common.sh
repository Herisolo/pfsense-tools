#!/bin/sh
#
# Common functions to be used by build scripts
#
# $Id$

# Fixup needed library changes above and beyond current release version if needed
fixup_libmap() {
	
}

check_for_clog() {
	if [ ! -d /usr/src/usr.sbin/clog ]; then
		echo "Could not find /usr/src/usr.sbin/clog.  Run cvsup_current.sh first!"
		exit
	fi
}

# This routine builds all kernels during the 
# build_iso.sh routines.
build_all_kernels() {
	# Build extra kernels (embedded, developers edition, etc)
	mkdir -p /tmp/kernels/wrap/boot/kernel
	mkdir -p /tmp/kernels/developers/boot/kernel
	mkdir -p /tmp/kernels/SMP/boot/kernel
	mkdir -p $PFSENSEBASEDIR/boot/kernel
	# Kernel will not install without these files
	echo -n ">>> Populating"
	echo -n " wrap"
	cp -R /boot/* /tmp/kernels/wrap/boot/
	echo -n " developers"
	cp -R /boot/* /tmp/kernels/developers/boot/
	echo -n " SMP"
	cp -R /boot/* /tmp/kernels/SMP/boot/
	find /tmp/kernels/ -name kernel.gz -exec rm {} \;
	# Copy pfSense kernel configuration files over to /usr/src/sys/i386/conf
	cp $BASE_DIR/tools/builder_scripts/conf/pfSense* /usr/src/sys/i386/conf/
	cp $BASE_DIR/tools/builder_scripts/conf/pfSense.6 /usr/src/sys/i386/conf/pfSense_SMP.6
	cp $BASE_DIR/tools/builder_scripts/conf/pfSense.7 /usr/src/sys/i386/conf/pfSense_SMP.7
	echo "" >> /usr/src/sys/i386/conf/pfSense_SMP.6
	echo "" >> /usr/src/sys/i386/conf/pfSense_SMP.7
	# Add SMP and APIC options
	echo "options 		SMP"   >> /usr/src/sys/i386/conf/pfSense_SMP.6
	echo "options 		SMP"   >> /usr/src/sys/i386/conf/pfSense_SMP.7
	echo "device 		apic" >> /usr/src/sys/i386/conf/pfSense_SMP.6
	echo "device 		apic" >> /usr/src/sys/i386/conf/pfSense_SMP.7
	echo "options		ALTQ_NOPCC" >> /usr/src/sys/i386/conf/pfSense_SMP.6
	echo "options		ALTQ_NOPCC" >> /usr/src/sys/i386/conf/pfSense_SMP.7
		# Build embedded kernel
		echo ">>> Building embedded kernel..."
		rm -rf /usr/obj
		(cd /usr/src && make buildkernel NO_KERNELCLEAN=yo KERNCONF=pfSense_wrap.$pfSense_version) 
		(cd /usr/src && make installkernel KERNCONF=pfSense_wrap.$pfSense_version DESTDIR=/tmp/kernels/wrap/)
		# Build SMP kernel
		echo ">>> Building SMP kernel..."
		rm -rf /usr/obj
		(cd /usr/src && make buildkernel NO_KERNELCLEAN=yo KERNCONF=pfSense_SMP.$pfSense_version) 
		(cd /usr/src && make installkernel KERNCONF=pfSense_SMP.$pfSense_version DESTDIR=/tmp/kernels/SMP/) 
		# Build Developers kernel
		echo ">>> Building Developers kernel..."
		rm -rf /usr/obj
		(cd /usr/src && make buildkernel NO_KERNELCLEAN=yo KERNCONF=pfSense_Dev.$pfSense_version) 
		(cd /usr/src && make installkernel KERNCONF=pfSense_Dev.$pfSense_version DESTDIR=/tmp/kernels/developers/)
	# GZIP kernels and make smaller
	echo
	echo -n ">>> GZipping: embedded"
	(cd /tmp/kernels/wrap/boot/kernel/ && gzip kernel)
	echo -n " SMP"
	(cd /tmp/kernels/SMP/boot/kernel/ && gzip kernel)
	echo -n " developers"
	(cd /tmp/kernels/developers/boot/kernel/ && gzip kernel)
	echo -n " ."
	# Move files into place
	mkdir -p $PFSENSEBASEDIR/kernels
	cp /tmp/kernels/wrap/boot/kernel/kernel.gz $PFSENSEBASEDIR/kernels/kernel_wrap.gz
	echo -n "."
	cp /tmp/kernels/SMP/boot/kernel/kernel.gz $PFSENSEBASEDIR/kernels/kernel_SMP.gz
	echo -n "."
	cp /tmp/kernels/developers/boot/kernel/kernel.gz $PFSENSEBASEDIR/kernels/kernel_Dev.gz
	echo "."
	rm -rf /tmp/kernels
}

recompile_pfPorts() {
	echo "===> Compiling pfPorts..."
	if [ -f /etc/make.conf ]; then
		mv /etc/make.conf /tmp/
	fi
	export FORCE_PKG_REGISTER=yo
	pfSDESTINATIONDIR=/usr/local
	pfSPORTS_BASE_DIR=/home/pfsense/tools
	mkdir -p $pfSDESTINATIONDIR
	mkdir -p $pfSDESTINATIONDIR/usr
	mkdir -p $pfSDESTINATIONDIR/var
	mkdir -p $pfSDESTINATIONDIR/root
	mkdir -p $pfSDESTINATIONDIR/usr/local
	mtree -PUer -q -p $pfSDESTINATIONDIR/usr < /etc/mtree/BSD.usr.dist
	mtree -PUer -q -p $pfSDESTINATIONDIR/var/ < /etc/mtree/BSD.var.dist
	mtree -PUer -q -p $pfSDESTINATIONDIR/root/ < /etc/mtree/BSD.root.dist
	mtree -PUer -q -p $pfSDESTINATIONDIR/usr/local < /etc/mtree/BSD.local.dist
	for pfSPORT in $INSTALL_PORTS; do
		echo > /etc/make.conf
		COMPILE_STATIC=""
		for STATIC in $STATIC_INSTALL_PORTS; do
			if [ "$STATIC" = "$pfSPORT" ]; then
				echo 'CFLAGS="-static"' >  /etc/make.conf
				echo "===> $STATIC is marked for static compilation..."
			fi
		done
		echo "===> Operating on $pfSPORT..."
		(cd $pfSPORTS_BASE_DIR/$pfSPORT && make FORCE_PKG_REGISTER=yo BATCH=yo $COMPILE_STATIC)
		echo "===> Installing new port..."
		(cd $pfSPORTS_BASE_DIR/$pfSPORT && make install FORCE_PKG_REGISTER=yo BATCH=yo)
	done
	chflags -R noschg $pfSDESTINATIONDIR
	if [ -f /tmp/make.conf ]; then
		mv /tmp/make.conf /etc/
	fi
	echo "===> End of pfPorts..."	
}

# Copies all extra files to the CVS staging area and ISO staging area (as needed)
populate_extra() {
    # Make devd
    ( cd ${SRCDIR}/sbin/devd; export __MAKE_CONF=${MAKE_CONF} NO_MAN=YES \
	make clean; make depend; make all; make DESTDIR=$CVS_CO_DIR install )

	mkdir -p ${CVS_CO_DIR}/lib

	if [ -f /usr/lib/pam_unix.so ]; then
		install -s /usr/lib/pam_unix.so ${CVS_CO_DIR}/usr/lib/
	fi
	
    mkdir -p $CVS_CO_DIR/var/run
    mkdir -p $CVS_CO_DIR/root/
    mkdir -p $CVS_CO_DIR/scripts/
    mkdir -p $CVS_CO_DIR/conf
    mkdir -p $CVS_CO_DIR/usr/local/bin/
    mkdir -p $CVS_CO_DIR/usr/local/share/dfuibe_installer/
    mkdir -p $CVS_CO_DIR/root

    echo exit > $CVS_CO_DIR/root/.xcustom.sh
    touch $CVS_CO_DIR/root/.hushlogin

    # bsnmpd
    mkdir -p $CVS_CO_DIR/usr/share/snmp/defs/
    cp -R /usr/share/snmp/defs/ $CVS_CO_DIR/usr/share/snmp/defs/

    # Add lua installer items
    mkdir -p $CVS_CO_DIR/usr/local/share/dfuibe_lua/

    # This is now ready for general consumption! \o/
    mkdir -p $CVS_CO_DIR/usr/local/share/dfuibe_lua/conf/
    cp -r $BASE_DIR/tools/installer/conf $CVS_CO_DIR/usr/local/share/dfuibe_lua/

	if [ $pfSense_version = "7" ]; then
		echo "Using FreeBSD 7 BSDInstaller dfuibelua structure."
    	cp -r $BASE_DIR/tools/installer/installer_root_dir7 $CVS_CO_DIR/usr/local/share/dfuibe_lua/install/
	else 
		echo "Using FreeBSD 6 BSDInstaller dfuibelua structure."
		cp -r $BASE_DIR/tools/installer/installer_root_dir $CVS_CO_DIR/usr/local/share/dfuibe_lua/install/
	fi

    # Set buildtime
    date > $CVS_CO_DIR/etc/version.buildtime
    cp $BASE_DIR/tools/pfi $CVS_CO_DIR/scripts/
    cp $BASE_DIR/tools/dev_bootstrap.sh $CVS_CO_DIR/scripts/
    cp $BASE_DIR/tools/lua_installer $CVS_CO_DIR/scripts/
    cp $BASE_DIR/tools/lua_installer $CVS_CO_DIR/scripts/installer
    chmod a+rx $CVS_CO_DIR/scripts/*
    cp $BASE_DIR/tools/after_installation_routines.sh \
	$CVS_CO_DIR/usr/local/bin/after_installation_routines.sh
    chmod a+rx $CVS_CO_DIR/scripts/*

    # Suppress extra spam when logging in
    touch $CVS_CO_DIR/root/.hushlogin

    # Setup login environment
    echo > $CVS_CO_DIR/root/.shrc
    echo "/etc/rc.initial" >> $CVS_CO_DIR/root/.shrc
    echo "exit" >> $CVS_CO_DIR/root/.shrc
    echo "/etc/rc.initial" >> $CVS_CO_DIR/root/.profile
    echo "exit" >> $CVS_CO_DIR/root/.profile

    # Trigger the pfSense wizzard
    echo "true" > $CVS_CO_DIR/trigger_initial_wizard

	# Turn off error checking
    set +e

    # Nuke CVS dirs
    find $CVS_CO_DIR -type d -name CVS -exec rm -rf {} \; 2> /dev/null
    find $CVS_CO_DIR -type d -name "_orange-flow" -exec rm -rf {} \; 2> /dev/null

	if [ $pfSense_version = "7" ]; then
	    echo "===> Building syslogd..."
	    (cd /usr/src/usr.sbin/syslogd && make clean && make && make install)
	    echo "===> Installing syslogd to $CVS_CO_DIR/usr/sbin/..."
	    install /usr/sbin/syslogd $CVS_CO_DIR/usr/sbin/
		echo "===> Building clog..."
		(cd /usr/src/usr.sbin/clog && make clean && make && make install)
	    echo "===> Installing clog to $CVS_CO_DIR/usr/sbin/..."
	    install /usr/sbin/clog $CVS_CO_DIR/usr/sbin/

		mkdir -p ${CVS_CO_DIR}/bin
		mkdir -p ${CVS_CO_DIR}/usr/bin

		# Populate PHP if it exists locally
		if [ -d /usr/local/lib/php/20060613/ ]; then
			if [ -d "${PFSENSEBASEDIR}/usr/local/lib/php/extensions/no-debug-non-zts-20020429" ]; then
				echo "Copying newer PHP binary and libraries..."
				if [ -e /usr/local/bin/php-cgi ]; then
					echo "Found php-cgi on local system, copying to staging area..."
					cp /usr/local/bin/php-cgi /usr/local/pfsense-fs/usr/local/bin/php
					chmod a+rx /usr/local/pfsense-fs/usr/local/bin/php
				fi
				cp -R "/usr/local/lib/php/20060613/" "${PFSENSEBASEDIR}/usr/local/lib/php/extensions/no-debug-non-zts-20020429/"
			fi
		fi

		# Process base system libraries
		FOUND_FILES="`(cd ${CVS_CO_DIR} && find sbin/ -type f)`"
		FOUND_FILES="$FOUND_FILES `(cd ${CVS_CO_DIR} && find lib/ -type f)`"
		FOUND_FILES="$FOUND_FILES `(cd ${CVS_CO_DIR} && find sbin/ -type f)`"
		FOUND_FILES="$FOUND_FILES `(cd ${CVS_CO_DIR} && find usr/bin/ -type f)`"
		FOUND_FILES="$FOUND_FILES `(cd ${CVS_CO_DIR} && find usr/sbin/ -type f)`"
		FOUND_FILES="$FOUND_FILES `(cd ${CVS_CO_DIR} && find usr/local/bin/ -type f)`"
		FOUND_FILES="$FOUND_FILES `(cd ${CVS_CO_DIR} && find usr/local/sbin/ -type f)`"
		FOUND_FILES="$FOUND_FILES `(cd ${CVS_CO_DIR} && find usr/lib/ -type f)`"
		FOUND_FILES="$FOUND_FILES `(cd ${CVS_CO_DIR} && find usr/local/lib/ -type f)`"
		NEEDEDLIBS=""
		echo ">>>> Populating newer binaries found on host jail/os (usr/local)..."
		for TEMPFILE in $FOUND_FILES; do
			if [ -f /$TEMPFILE ]; then
				FILETYPE=`file /$TEMPFILE | grep dynamically | wc -l | awk '{ print $1 }'`
				if [ "$FILETYPE" -gt 0 ]; then
					NEEDEDLIBS="$NEEDEDLIBS `ldd /$TEMPFILE | grep "=>" | awk '{ print $3 }'`"									
					cp /$TEMPFILE ${PFSENSEBASEDIR}/$TEMPFILE
					echo "cp /$TEMPFILE ${PFSENSEBASEDIR}/$TEMPFILE"
				fi
			else
				FILETYPE=`file ${CVS_CO_DIR}/$TEMPFILE | grep dynamically | wc -l | awk '{ print $1 }'`
				if [ "$FILETYPE" -gt 0 ]; then
					NEEDEDLIBS="$NEEDEDLIBS `ldd ${CVS_CO_DIR}/$TEMPFILE | grep "=>" | awk '{ print $3 }'`"									
				fi
			fi
		done		
		echo ">>>> Installing collected library information (usr/local), please wait..."
		for NEEDLIB in $NEEDEDLIBS; do
			if [ -f $NEEDLIB ]; then 
				install $NEEDLIB ${PFSENSEBASEDIR}${NEEDLIB}
				echo "install $NEEDLIB ${PFSENSEBASEDIR}${NEEDLIB}"
			fi
		done
		
		# Populate PHP if it exists locally
		if [ -d /usr/local/lib/php/20060613/ ]; then
			if [ -d "${PFSENSEBASEDIR}/usr/local/lib/php/extensions/no-debug-non-zts-20020429" ]; then
				echo "Copying newer PHP binary and libraries..."
				cp -R "/usr/local/lib/php/20060613/" "${PFSENSEBASEDIR}/usr/local/lib/php/extensions/no-debug-non-zts-20020429/"
			fi
		fi

	    set -e

	fi
		
	# Extract custom overlay if it's defined.
	if [ ! -z "${custom_overlay:-}" ]; then
		echo -n "Custom overlay defined - "
                if [ -d $custom_overlay ]; then
                        echo "found directory, copying..."
                        for i in $custom_overlay/*
                        do
                            if [ -d $i ]; then
                                echo "copying dir: $i ..."
                                cp -R $i $CVS_CO_DIR
                            else
                                echo "copying file: $i ..."
                                cp $i $CVS_CO_DIR
                            fi
                        done
		elif [ -f $custom_overlay ]; then
			echo "found file, extracting..."
			tar xzpf $custom_overlay -C $CVS_CO_DIR
		else
			echo " file not found $custom_overlay"
		fi
	fi

    # Enable debug if requested
    if [ ! -z "${PFSENSE_DEBUG:-}" ]; then
		touch ${CVS_CO_DIR}/debugging
    fi
}

install_custom_packages() {
	DEVFS_MOUNT=`mount | grep /usr/local/pfsense-fs/dev`
	DESTNAME="pkginstall.sh"

	if [ -n ${DEVFS_MOUNT} ]; then
		if [ -d ${BASEDIR}/dev ]; then
			umount ${BASEDIR}/dev
		fi
	fi

	# Extra package list if defined.
	if [ ! -z "${custom_package_list:-}" ]; then
		# execute setup script
		./pfs_custom_pkginstall.sh
	else
		# cleanup if file does exist
		if [ -f ${FREESBIE_PATH}/extra/customscripts/${DESTNAME} ]; then
			rm ${FREESBIE_PATH}/extra/customscripts/${DESTNAME}
		fi
	fi
}

create_pfSense_BaseSystem_Small_update_tarball() {
	VERSION=`cat $CVS_CO_DIR/etc/version`
	FILENAME=pfSense-Mini-Embedded-BaseSystem-Update-${VERSION}.tgz

	mkdir -p $UPDATESDIR

	echo ; echo Creating ${UPDATESDIR}/${FILENAME} ...

	cp ${CVS_CO_DIR}/usr/local/sbin/check_reload_status /tmp/
	cp ${CVS_CO_DIR}/usr/local/sbin/mpd /tmp/

	rm -rf ${CVS_CO_DIR}/usr/local/sbin/*
	rm -rf ${CVS_CO_DIR}/usr/local/bin/*
	install -s /tmp/check_reload_status ${CVS_CO_DIR}/usr/local/sbin/check_reload_status
	install -s /tmp/mpd ${CVS_CO_DIR}/usr/local/sbin/mpd

	du -hd0 ${CVS_CO_DIR}

	rm -f ${CVS_CO_DIR}/etc/platform
	rm -f ${CVS_CO_DIR}/etc/*passwd*
	rm -f ${CVS_CO_DIR}/etc/pw*
	rm -f ${CVS_CO_DIR}/etc/ttys

	# Nuke /root/ directory contents
	rm -rf ${CVS_CO_DIR}/root

	cd ${CVS_CO_DIR} && tar czPf ${UPDATESDIR}/${FILENAME} .

	ls -lah ${UPDATESDIR}/${FILENAME}

	gzsig sign ~/.ssh/id_dsa ${UPDATESDIR}/${FILENAME}
}

fixup_updates() {

	cd ${PFSENSEBASEDIR}
	rm -rf ${PFSENSEBASEDIR}/cf
	rm -rf ${PFSENSEBASEDIR}/conf
	find ${PFSENSEBASEDIR}/boot/ -type f -depth 1 -exec rm {} \;
	rm -rf ${PFSENSEBASEDIR}/etc/rc.conf
	rm -rf ${PFSENSEBASEDIR}/etc/motd
	rm -rf ${PFSENSEBASEDIR}/trigger*
	echo Removing pfSense.tgz used by installer..
	find ${PFSENSEBASEDIR} -name pfSense.tgz -exec rm {} \;
	rm -f ${PFSENSEBASEDIR}/etc/pwd.db 2>/dev/null
	rm -f ${PFSENSEBASEDIR}/etc/group 2>/dev/null
	rm -f ${PFSENSEBASEDIR}/etc/spwd.db 2>/dev/null
	rm -f ${PFSENSEBASEDIR}/etc/passwd 2>/dev/null
	rm -f ${PFSENSEBASEDIR}/etc/master.passwd 2>/dev/null
	rm -f ${PFSENSEBASEDIR}/etc/fstab 2>/dev/null
	#rm -f ${PFSENSEBASEDIR}/etc/ttys 2>/dev/null
	rm -f ${PFSENSEBASEDIR}/etc/platform 2>/dev/null
	echo > ${PFSENSEBASEDIR}/root/.tcshrc
	echo "alias installer /scripts/lua_installer" > ${PFSENSEBASEDIR}/root/.tcshrc
	# Setup login environment
	echo > ${PFSENSEBASEDIR}/root/.shrc
	echo "/etc/rc.initial" >> ${PFSENSEBASEDIR}/root/.shrc
	echo "exit" >> ${PFSENSEBASEDIR}/root/.shrc

	# Nuke the trigger wizard script
	rm -f ${PFSENSEBASEDIR}/trigger_initial_wizard

	mkdir -p ${PFSENSEBASEDIR}/usr/local/livefs/lib/

	echo `date` > ${PFSENSEBASEDIR}/etc/version.buildtime
}

fixup_wrap() {

    cp $CVS_CO_DIR/boot/device.hints_wrap \
            $CVS_CO_DIR/boot/device.hints
    cp $CVS_CO_DIR/boot/loader.conf_wrap \
            $CVS_CO_DIR/boot/loader.conf
    cp $CVS_CO_DIR/etc/ttys_wrap \
            $CVS_CO_DIR/etc/ttys

    echo `date` > $CVS_CO_DIR/etc/version.buildtime
    echo "" > $CVS_CO_DIR/etc/motd

    mkdir -p $CVS_CO_DIR/cf/conf/backup

    # Nuke the trigger wizard script
    rm -f $CVS_CO_DIR/trigger_initial_wizard

    echo /etc/rc.initial > $CVS_CO_DIR/root/.shrc
    echo exit >> $CVS_CO_DIR/root/.shrc
    rm -f $CVS_CO_DIR/usr/local/bin/after_installation_routines.sh 2>/dev/null

    touch $CVS_CO_DIR/conf/trigger_initial_wizard

    echo "embedded" > $CVS_CO_DIR/etc/platform
    echo "wrap" > /boot/kernel/pfsense_kernel.txt

    rm -rf $CVS_CO_DIR/conf
    ln -s /cf/conf $CVS_CO_DIR/conf
}

create_FreeBSD_system_update() {
	VERSION="FreeBSD"
	FILENAME=pfSense-Embedded-Update-${VERSION}.tgz
	mkdir -p $UPDATESDIR

	cd ${CLONEDIR}
	# Remove some fat and or conflicting
	# freebsd files
	rm -rf etc/
	rm -rf var/
	rm -rf usr/share/
	rm -rf root/
	echo "Creating ${UPDATESDIR}/${FILENAME} update file..."
	tar czPf ${UPDATESDIR}/${FILENAME} .

	echo "Signing ${UPDATESDIR}/${FILENAME} update file..."
	gzsig sign ~/.ssh/id_dsa ${UPDATESDIR}/${FILENAME}
}

create_pfSense_Full_update_tarball() {
	VERSION=`cat ${PFSENSEBASEDIR}/etc/version`
	FILENAME=pfSense-Full-Update-${VERSION}-`date "+%Y%m%d-%H%M"`.tgz
	mkdir -p $UPDATESDIR

	echo ; echo "Deleting files listed in ${PRUNE_LIST}"
	set +e
	(cd ${PFSENSEBASEDIR} && sed 's/^#.*//g' ${PRUNE_LIST} | xargs rm -rvf > /dev/null 2>&1)

	echo ; echo Creating ${UPDATESDIR}/${FILENAME} ...
	cd ${PFSENSEBASEDIR} && tar czPf ${UPDATESDIR}/${FILENAME} .

	echo "Signing ${UPDATESDIR}/${FILENAME} update file..."
	gzsig sign ~/.ssh/id_dsa ${UPDATESDIR}/${FILENAME}
}

create_pfSense_Embedded_update_tarball() {
	VERSION=`cat ${PFSENSEBASEDIR}/etc/version`
	FILENAME=pfSense-Embedded-Update-${VERSION}-`date "+%Y%m%d-%H%M"`.tgz
	mkdir -p $UPDATESDIR

	echo ; echo "Deleting files listed in ${PRUNE_LIST}"
	set +e
	(cd ${PFSENSEBASEDIR} && sed 's/^#.*//g' ${PRUNE_LIST} | xargs rm -rvf > /dev/null 2>&1)

	# Remove all other kernels and replace full kernel with the embedded
	# kernel that was built during the builder process
	mv ${PFSENSEBASEDIR}/kernels/kernel_wrap.gz ${PFSENSEBASEDIR}/boot/kernel/kernel.gz
	rm -rf ${PFSENSEBASEDIR}/kernels/*

	echo ; echo Creating ${UPDATESDIR}/${FILENAME} ...
	cd ${PFSENSEBASEDIR} && tar czPf ${UPDATESDIR}/${FILENAME} .

	echo "Signing ${UPDATESDIR}/${FILENAME} update file..."
	gzsig sign ~/.ssh/id_dsa ${UPDATESDIR}/${FILENAME}
}

create_pfSense_Small_update_tarball() {
	VERSION=`cat $CVS_CO_DIR/etc/version`
	FILENAME=pfSense-Mini-Embedded-Update-${VERSION}-`date "+%Y%m%d-%H%M"`.tgz

	mkdir -p $UPDATESDIR

	echo ; echo Creating ${UPDATESDIR}/${FILENAME} ...

	cp ${CVS_CO_DIR}/usr/local/sbin/check_reload_status /tmp/
	cp ${CVS_CO_DIR}/usr/local/sbin/mpd /tmp/

	rm -rf ${CVS_CO_DIR}/usr/local/sbin/*
	rm -rf ${CVS_CO_DIR}/usr/local/bin/*
	install -s /tmp/check_reload_status ${CVS_CO_DIR}/usr/local/sbin/check_reload_status
	install -s /tmp/mpd ${CVS_CO_DIR}/usr/local/sbin/mpd

	du -hd0 ${CVS_CO_DIR}

	rm -f ${CVS_CO_DIR}/etc/platform
	rm -f ${CVS_CO_DIR}/etc/*passwd*
	rm -f ${CVS_CO_DIR}/etc/pw*
	rm -f ${CVS_CO_DIR}/etc/ttys*
	
	cd ${CVS_CO_DIR} && tar czPf ${UPDATESDIR}/${FILENAME} .

	ls -lah ${UPDATESDIR}/${FILENAME}

	gzsig sign ~/.ssh/id_dsa ${UPDATESDIR}/${FILENAME}

}

# Create tarball of pfSense cvs directory
create_pfSense_tarball() {
	rm -f $CVS_CO_DIR/boot/*

	find $CVS_CO_DIR -name CVS -exec rm -rf {} \; 2>/dev/null
	find $CVS_CO_DIR -name "_orange-flow" -exec rm -rf {} \; 2>/dev/null

	cd $CVS_CO_DIR && tar czPf /tmp/pfSense.tgz .
}

# Copy tarball of pfSense cvs directory to FreeSBIE custom directory
copy_pfSense_tarball_to_custom_directory() {
	rm -rf $LOCALDIR/customroot/*

	tar  xzPf /tmp/pfSense.tgz -C $LOCALDIR/customroot/

	rm -f $LOCALDIR/customroot/boot/*
	rm -rf $LOCALDIR/customroot/cf/conf/config.xml
	rm -rf $LOCALDIR/customroot/conf/config.xml
	rm -rf $LOCALDIR/customroot/conf
	mkdir -p $LOCALDIR/customroot/conf

	mkdir -p $LOCALDIR/var/db/
	chroot $LOCALDIR /bin/ln -s /var/db/rrd /usr/local/www/rrd

	chroot $LOCALDIR/ cap_mkdb /etc/master.passwd

}

copy_pfSense_tarball_to_freesbiebasedir() {
	cd $LOCALDIR

	tar  xzPf /tmp/pfSense.tgz -C $FREESBIEBASEDIR
}

# Set image as a CDROM type image
set_image_as_cdrom() {
	touch $CVS_CO_DIR/conf/trigger_initial_wizard
	echo cdrom > $CVS_CO_DIR/etc/platform
}

#Create a copy of FREESBIEBASEDIR. This is useful to modify the live filesystem
clone_system_only()
{
  echo -n "Cloning $FREESBIEBASEDIR to $FREESBIEISODIR..."

  mkdir -p $FREESBIEISODIR || print_error
  if [ -r $FREESBIEISODIR ]; then
        chflags -R noschg $FREESBIEISODIR || print_error
        rm -rf $FREESBIEISODIR/* || print_error
  fi

  #We are making files containing /usr and /var partition

  #Before uzip'ing filesystems, we have to save the directories tree
  mkdir -p $FREESBIEISODIR/dist
  mtree -Pcdp $FREESBIEBASEDIR/usr > $FREESBIEISODIR/dist/FreeSBIE.usr.dirs
  mtree -Pcdp $FREESBIEBASEDIR/var > $FREESBIEISODIR/dist/FreeSBIE.var.dirs

  #Define a function to create the vnode $1 of the size expected for
  #$FREESBIEBASEDIR/$2 directory, mount it under $FREESBIEISODIR/$2
  #and print the md device
  create_vnode() {
      UFSFILE=$1
      CLONEDIR=$FREESBIEBASEDIR/$2
      MOUNTPOINT=$FREESBIEISODIR/$2
      cd $CLONEDIR
      FSSIZE=$((`du -kd 0 | cut -f 1` + 94000))
      dd if=/dev/zero of=$UFSFILE bs=1k count=$FSSIZE > /dev/null 2>&1

      DEVICE=/dev/`mdconfig -a -t vnode -f $UFSFILE`
      newfs $DEVICE > /dev/null 2>&1
      mkdir -p $MOUNTPOINT
      mount -o noatime ${DEVICE} $MOUNTPOINT
      echo ${DEVICE}
  }

  #Umount and detach md devices passed as parameters
  umount_devices() {
      for i in $@; do
          umount ${i}
          mdconfig -d -u ${i}
      done
  }

  mkdir -p $FREESBIEISODIR/uzip
  MDDEVICES=`create_vnode $FREESBIEISODIR/uzip/usr.ufs usr`
  MDDEVICES="$MDDEVICES `create_vnode $FREESBIEISODIR/uzip/var.ufs var`"

  trap "umount_devices $MDDEVICES; exit 1" INT

  cd $FREESBIEBASEDIR

  find . -print -depth | cpio --quiet -pudm $FREESBIEISODIR

  umount_devices $MDDEVICES

  trap "" INT

  echo " [DONE]"
}

checkout_pfSense() {
        echo ">>> Getting pfSense"
        rm -rf $CVS_CO_DIR
	cd $BASE_DIR && cvs -d /home/pfsense/cvsroot co pfSense -r ${PFSENSETAG}
	fixup_libmap
}

checkout_freesbie() {
        echo ">>> Getting FreeSBIE"
        rm -rf $LOCALDIR
}

print_flags() {
        if [ $BE_VERBOSE = "yes" ]
        then
                echo "Current flags:"
                printf "\tbuilder.sh\n"
                printf "\t\tCVS User: %s\n" $CVS_USER
                printf "\t\tVerbosity: %s\n" $BE_VERBOSE
                printf "\t\tTargets:%s\n" "$TARGETS"
                printf "\tconfig.sh\n"
                printf "\t\tLiveFS dir: %s\n" $FREESBIEBASEDIR
                printf "\t\tFreeSBIE dir: %s\n" $LOCALDIR
                printf "\t\tISO dir: %s\n" $PATHISO
                printf "\tpfsense_local.sh\n"
                printf "\t\tBase dir: %s\n" $BASE_DIR
                printf "\t\tCheckout dir: %s\n\n" $CVS_CO_DIR
        fi
}

clear_custom() {
        echo ">> Clearing custom/*"
        rm -rf $LOCALDIR/customroot/*
}

backup_pfSense() {
        echo ">>> Backing up pfSense repo"
        cp -R $CVS_CO_DIR $BASE_DIR/pfSense_bak
}

restore_pfSense() {
        echo ">>> Restoring pfSense repo"
        cp -R $BASE_DIR/pfSense_bak $CVS_CO_DIR
}

freesbie_make() {
	(cd ${FREESBIE_PATH} && make $*)
}

update_cvs_depot() {
    # Update cvs depot. If SKIP_RSYNC is defined, skip the RSYNC update
    # and prompt if the operator would like to download cvs.tgz from pfsense.com.
    # If also SKIP_CHECKOUT is defined, don't update the tree at all
    if [ -z "${SKIP_RSYNC:-}" ]; then
		rm -rf $BASE_DIR/pfSense
		rsync -avz ${CVS_USER}@${CVS_IP}:/cvsroot /home/pfsense/
		(cd $BASE_DIR && cvs -d /home/pfsense/cvsroot co -r ${PFSENSETAG} pfSense)
		fixup_libmap
		else
		cvsup pfSense-supfile
		rm -rf pfSense
		rm -rf $BASE_DIR/pfSense
		(cd $BASE_DIR && cvs -d /home/pfsense/cvsroot co -r ${PFSENSETAG} pfSense)
		(cd $BASE_DIR/tools/ && cvs update -d)
		fixup_libmap
    fi
}

make_world_kernel() {
    # Check if the world and kernel are already built and set
    # the NO variables accordingly
    objdir=${MAKEOBJDIRPREFIX:-/usr/obj}
    build_id_w=`basename ${KERNELCONF}`
    build_id_k=${build_id_w}

    # If PFSENSE_DEBUG is set, build debug kernel, if a .DEBUG kernel
    # configuration file exists
    if [ ! -z "${PFSENSE_DEBUG:-}" -a -f ${KERNELCONF}.DEBUG ]; then
	# Yes, use it
	export KERNELCONF=${KERNELCONF}.DEBUG
	build_id_k=${build_id_w}.DEBUG
    fi

    if [ -f "${objdir}/${build_id_w}.world.done" ]; then
	export NO_BUILDWORLD=yo
    fi
    if [ -f "${objdir}/${build_id_k}.kernel.done" ]; then
	export NO_BUILDKERNEL=yo
    fi

    # Make world
    freesbie_make buildworld
    touch ${objdir}/${build_id_w}.world.done

    # Make kernel
    freesbie_make buildkernel
    touch ${objdir}/${build_id_k}.kernel.done

    freesbie_make installkernel installworld
}

