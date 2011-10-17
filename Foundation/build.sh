# project settings
export SOURCES="Sources/NS*.m Sources/Externs.m Sources/Unicode.m"   # all source codes
# export SOURCES="Sources/NSString.m Sources/Externs.m Sources/Unicode.m"   # all source codes
export LIBS="-Uobjc_main -lm -ldl -lpthread -lssl -lcrypto -lobjc"   # add any additional libraries (or flags) like -ltiff etc.
export FRAMEWORKS=				   # add any additional Frameworks etc.
export INSTALL_PATH=/System/Library/Frameworks   # override INSTALL_PATH for MacOS X for Zaurus

# global/compile settings
#export INSTALL=true                # true (or empty) will install locally to $ROOT/$INSTALL_PATH
#export SEND2ZAURUS=true		   # true (or empty) will try to install on the Zaurus at /$INSTALL_PATH (using ssh)
#export RUN=true                    # true (or empty) will finally try to run on the Zaurus (using X11 on host)
export DEPENDS="libc6 (>= 2.7-1), libobjc2, libssl0.9.8"      # debian package dependencies

[ "$ROOT" ] || export ROOT=/usr/share/QuantumSTEP	# project root
/usr/bin/make -f $ROOT/System/Sources/Frameworks/mySTEP.make $ACTION
