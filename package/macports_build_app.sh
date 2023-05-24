#!/bin/sh

# set -e

PREFIX=/opt/local
if [[ $(uname -m) == 'arm64' ]]; then
  build_arm64=true
  echo "*** Build: arm64"
  #  target directory
  export PACKAGE_DIR="${HOME}/macports-gimp299-osx-app"
  export arch="arm64"
else
  build_arm64=false
  echo "*** Build: x86_64"
  #  target directory
  export PACKAGE_DIR="${HOME}/macports-gimp299-osx-app-x86_64"
  export arch="x86_64"
fi
export JHBUILD_PREFIX=${PREFIX}
GTK_MAC_BUNDLER=${HOME}/.local/bin/gtk-mac-bundler

printf "Determining GIMP version: "

GIMP_VERSION="$(${PREFIX}/bin/gimp-2.99 --version 2>/dev/null | grep 'GNU Image Manipulation Program version' | sed 's|GNU Image Manipulation Program version ||')"
# for gtk-mac-bundler

echo "$GIMP_VERSION"

cat info.plist.tmpl | sed "s|%VERSION%|${GIMP_VERSION}|g" > info.plist

echo "Copying charset.alias"
sudo cp -f "/usr/lib/charset.alias" "${PREFIX}/lib/"

echo "Creating bundle"
$GTK_MAC_BUNDLER macports-gimp.bundle
if [ ! -f ${PACKAGE_DIR}/GIMP.app/Contents/MacOS/gimp ]; then
  echo "ERROR: Bundling failed, ${PACKAGE_DIR}/GIMP.app/Contents/MacOS/gimp not found"
  exit 1
fi
echo "Done creating bundle"

echo "Store GIMP version in bundle (for later use)"
echo "$GIMP_VERSION" > ${PACKAGE_DIR}/GIMP.app/Contents/Resources/.version

BASEDIR=$(dirname "$0")

echo "Link 'Resources' into python framework 'Resources'"
if [ ! -d "${PACKAGE_DIR}/GIMP.app/Contents/Resources/Library/Frameworks/Python.framework/Versions/3.10/Resources/Python.app/Contents/Resources" ]; then
  # Avoids creating very awkward link in the wrong place
  echo "***Error: Python framework not found"
  exit 1
fi
pushd "${PACKAGE_DIR}/GIMP.app/Contents/Resources/Library/Frameworks/Python.framework/Versions/3.10/Resources/Python.app/Contents/Resources/"
  for resources in etc gimp.icns lib share xcf.icns ;
  do
    ln -s "../../../../../../../../../${resources}" \
      "${resources}"
  done
popd

echo "Removing pathnames from the libraries and binaries"
# fix permission for some libs
find  ${PACKAGE_DIR}/GIMP.app/Contents/Resources \( -name '*.dylib' -o -name '*.so' \) -type f | xargs chmod 755
# getting list of the files to fix
FILES=$(
  find ${PACKAGE_DIR}/GIMP.app -perm +111 -type f \
   | xargs file \
   | grep ' Mach-O '|awk -F ':' '{print $1}'
)

OLDPATH="${PREFIX}/"

for file in $FILES
do
  id_path=$(echo "$file" | sed -E "s|${PACKAGE_DIR}/GIMP.app/Contents/(Resources\|MacOS)/||")
  install_name_tool -id "@rpath/"$id_path $file
  otool -L $file \
   | grep "\t$OLDPATH" \
   | sed "s|${OLDPATH}||" \
   | awk -v fname="$file" -v old_path="$OLDPATH" '{print "install_name_tool -change "old_path $1" @rpath/"$1" "fname}' \
   | bash
done

# Long list of -change are due to not building gcc from source
# due to a bug. See https://trac.macports.org/ticket/65573
echo "adding @rpath to the binaries (incl special ghostscript 9.56 fix)"
find  ${PACKAGE_DIR}/GIMP.app/Contents/MacOS -type f -perm +111 \
   | xargs file \
   | grep ' Mach-O ' |awk -F ':' '{print $1}' \
   | xargs -n1 install_name_tool -add_rpath @executable_path/../Resources/ \
       -change @rpath/libgfortran.5.dylib @rpath/lib/libgcc/libgfortran.5.dylib \
       -change @rpath/libgfortran.dylib   @rpath/lib/libgcc/libgfortran.dylib \
       -change @rpath/libquadmath.0.dylib @rpath/lib/libgcc/libquadmath.0.dylib \
       -change @rpath/libquadmath.dylib   @rpath/lib/libgcc/libquadmath.dylib \
       -change @rpath/libstdc++.6.dylib   @rpath/lib/libgcc/libstdc++.6.dylib \
       -change @rpath/libstdc++.dylib     @rpath/lib/libgcc/libstdc++.dylib \
       -change @rpath/libgcc_s.1.1.dylib  @rpath/lib/libgcc/libgcc_s.1.1.dylib \
       -change @rpath//libasan.8.dylib    @rpath/lib/libgcc/libasan.8.dylib \
       -change @rpath/libasan.dylib       @rpath/lib/libgcc/libasan.dylib \
       -change @rpath/libatomic.1.dylib   @rpath/lib/libgcc/libatomic.1.dylib \
       -change @rpath/libatomic.dylib     @rpath/lib/libgcc/libatomic.dylib \
       -change @rpath/libgcc_s.1.dylib    @rpath/lib/libgcc/libgcc_s.1.dylib \
       -change @rpath/libgcc_s.dylib      @rpath/lib/libgcc/libgcc_s.dylib \
       -change @rpath/libgomp.1.dylib     @rpath/lib/libgcc/libgomp.1.dylib \
       -change @rpath/libgomp.dylib       @rpath/lib/libgcc/libgomp.dylib \
       -change @rpath/libitm.1.dylib      @rpath/lib/libgcc/libitm.1.dylib \
       -change @rpath/libitm.dylib        @rpath/lib/libgcc/libitm.dylib \
       -change @rpath/libobjc-gnu.4.dylib @rpath/lib/libgcc/libobjc-gnu.4.dylib \
       -change @rpath/libobjc-gnu.dylib   @rpath/lib/libgcc/libobjc-gnu.dylib \
       -change @rpath/libssp.0.dylib      @rpath/lib/libgcc/libssp.0.dylib \
       -change @rpath/libssp.dylib        @rpath/lib/libgcc/libssp.dylib \
       -change @rpath/libubsan.1.dylib    @rpath/lib/libgcc/libubsan.1.dylib \
       -change @rpath/libubsan.dylib      @rpath/lib/libgcc/libubsan.dylib

echo "adding @rpath to the plugins (incl special ghostscript 9.56 fix)"
find  ${PACKAGE_DIR}/GIMP.app/Contents/Resources/lib/gimp/2.99/plug-ins/ -perm +111 -type f \
   | xargs file \
   | grep ' Mach-O '|awk -F ':' '{print $1}' \
   | xargs -n1 install_name_tool -add_rpath @executable_path/../../../../../ \
       -change @rpath/libgfortran.5.dylib @rpath/lib/libgcc/libgfortran.5.dylib \
       -change @rpath/libgfortran.dylib   @rpath/lib/libgcc/libgfortran.dylib \
       -change @rpath/libquadmath.0.dylib @rpath/lib/libgcc/libquadmath.0.dylib \
       -change @rpath/libquadmath.dylib   @rpath/lib/libgcc/libquadmath.dylib \
       -change @rpath/libstdc++.6.dylib   @rpath/lib/libgcc/libstdc++.6.dylib \
       -change @rpath/libstdc++.dylib     @rpath/lib/libgcc/libstdc++.dylib \
       -change @rpath/libgcc_s.1.1.dylib  @rpath/lib/libgcc/libgcc_s.1.1.dylib \
       -change @rpath//libasan.8.dylib    @rpath/lib/libgcc/libasan.8.dylib \
       -change @rpath/libasan.dylib       @rpath/lib/libgcc/libasan.dylib \
       -change @rpath/libatomic.1.dylib   @rpath/lib/libgcc/libatomic.1.dylib \
       -change @rpath/libatomic.dylib     @rpath/lib/libgcc/libatomic.dylib \
       -change @rpath/libgcc_s.1.dylib    @rpath/lib/libgcc/libgcc_s.1.dylib \
       -change @rpath/libgcc_s.dylib      @rpath/lib/libgcc/libgcc_s.dylib \
       -change @rpath/libgomp.1.dylib     @rpath/lib/libgcc/libgomp.1.dylib \
       -change @rpath/libgomp.dylib       @rpath/lib/libgcc/libgomp.dylib \
       -change @rpath/libitm.1.dylib      @rpath/lib/libgcc/libitm.1.dylib \
       -change @rpath/libitm.dylib        @rpath/lib/libgcc/libitm.dylib \
       -change @rpath/libobjc-gnu.4.dylib @rpath/lib/libgcc/libobjc-gnu.4.dylib \
       -change @rpath/libobjc-gnu.dylib   @rpath/lib/libgcc/libobjc-gnu.dylib \
       -change @rpath/libssp.0.dylib      @rpath/lib/libgcc/libssp.0.dylib \
       -change @rpath/libssp.dylib        @rpath/lib/libgcc/libssp.dylib \
       -change @rpath/libubsan.1.dylib    @rpath/lib/libgcc/libubsan.1.dylib \
       -change @rpath/libubsan.dylib      @rpath/lib/libgcc/libubsan.dylib

echo "adding @rpath to the extensions (incl special ghostscript 9.56 fix)"
find  ${PACKAGE_DIR}/GIMP.app/Contents/Resources/lib/gimp/2.99/extensions/ -perm +111 -type f \
   | xargs file \
   | grep ' Mach-O '|awk -F ':' '{print $1}' \
   | xargs -n1 install_name_tool -add_rpath @executable_path/../../../../../ \
       -change @rpath/libgfortran.5.dylib @rpath/lib/libgcc/libgfortran.5.dylib \
       -change @rpath/libgfortran.dylib   @rpath/lib/libgcc/libgfortran.dylib \
       -change @rpath/libquadmath.0.dylib @rpath/lib/libgcc/libquadmath.0.dylib \
       -change @rpath/libquadmath.dylib   @rpath/lib/libgcc/libquadmath.dylib \
       -change @rpath/libstdc++.6.dylib   @rpath/lib/libgcc/libstdc++.6.dylib \
       -change @rpath/libstdc++.dylib     @rpath/lib/libgcc/libstdc++.dylib \
       -change @rpath/libgcc_s.1.1.dylib  @rpath/lib/libgcc/libgcc_s.1.1.dylib \
       -change @rpath//libasan.8.dylib    @rpath/lib/libgcc/libasan.8.dylib \
       -change @rpath/libasan.dylib       @rpath/lib/libgcc/libasan.dylib \
       -change @rpath/libatomic.1.dylib   @rpath/lib/libgcc/libatomic.1.dylib \
       -change @rpath/libatomic.dylib     @rpath/lib/libgcc/libatomic.dylib \
       -change @rpath/libgcc_s.1.dylib    @rpath/lib/libgcc/libgcc_s.1.dylib \
       -change @rpath/libgcc_s.dylib      @rpath/lib/libgcc/libgcc_s.dylib \
       -change @rpath/libgomp.1.dylib     @rpath/lib/libgcc/libgomp.1.dylib \
       -change @rpath/libgomp.dylib       @rpath/lib/libgcc/libgomp.dylib \
       -change @rpath/libitm.1.dylib      @rpath/lib/libgcc/libitm.1.dylib \
       -change @rpath/libitm.dylib        @rpath/lib/libgcc/libitm.dylib \
       -change @rpath/libobjc-gnu.4.dylib @rpath/lib/libgcc/libobjc-gnu.4.dylib \
       -change @rpath/libobjc-gnu.dylib   @rpath/lib/libgcc/libobjc-gnu.dylib \
       -change @rpath/libssp.0.dylib      @rpath/lib/libgcc/libssp.0.dylib \
       -change @rpath/libssp.dylib        @rpath/lib/libgcc/libssp.dylib \
       -change @rpath/libubsan.1.dylib    @rpath/lib/libgcc/libubsan.1.dylib \
       -change @rpath/libubsan.dylib      @rpath/lib/libgcc/libubsan.dylib

echo "adding @rpath to libgcc dylibs"
find  ${PACKAGE_DIR}/GIMP.app/Contents/Resources/lib/ -perm +111 -type f \
   | xargs file \
   | grep ' Mach-O '|awk -F ':' '{print $1}' \
   | xargs -n1 install_name_tool \
       -change @rpath/libgfortran.5.dylib @rpath/lib/libgcc/libgfortran.5.dylib \
       -change @rpath/libgfortran.dylib   @rpath/lib/libgcc/libgfortran.dylib \
       -change @rpath/libquadmath.0.dylib @rpath/lib/libgcc/libquadmath.0.dylib \
       -change @rpath/libquadmath.dylib   @rpath/lib/libgcc/libquadmath.dylib \
       -change @rpath/libstdc++.6.dylib   @rpath/lib/libgcc/libstdc++.6.dylib \
       -change @rpath/libstdc++.dylib     @rpath/lib/libgcc/libstdc++.dylib \
       -change @rpath/libgcc_s.1.1.dylib  @rpath/lib/libgcc/libgcc_s.1.1.dylib \
       -change @rpath//libasan.8.dylib    @rpath/lib/libgcc/libasan.8.dylib \
       -change @rpath/libasan.dylib       @rpath/lib/libgcc/libasan.dylib \
       -change @rpath/libatomic.1.dylib   @rpath/lib/libgcc/libatomic.1.dylib \
       -change @rpath/libatomic.dylib     @rpath/lib/libgcc/libatomic.dylib \
       -change @rpath/libgcc_s.1.dylib    @rpath/lib/libgcc/libgcc_s.1.dylib \
       -change @rpath/libgcc_s.dylib      @rpath/lib/libgcc/libgcc_s.dylib \
       -change @rpath/libgomp.1.dylib     @rpath/lib/libgcc/libgomp.1.dylib \
       -change @rpath/libgomp.dylib       @rpath/lib/libgcc/libgomp.dylib \
       -change @rpath/libitm.1.dylib      @rpath/lib/libgcc/libitm.1.dylib \
       -change @rpath/libitm.dylib        @rpath/lib/libgcc/libitm.dylib \
       -change @rpath/libobjc-gnu.4.dylib @rpath/lib/libgcc/libobjc-gnu.4.dylib \
       -change @rpath/libobjc-gnu.dylib   @rpath/lib/libgcc/libobjc-gnu.dylib \
       -change @rpath/libssp.0.dylib      @rpath/lib/libgcc/libssp.0.dylib \
       -change @rpath/libssp.dylib        @rpath/lib/libgcc/libssp.dylib \
       -change @rpath/libubsan.1.dylib    @rpath/lib/libgcc/libubsan.1.dylib \
       -change @rpath/libubsan.dylib      @rpath/lib/libgcc/libubsan.dylib

echo "adding @rpath to python app"
install_name_tool -add_rpath @loader_path/../../../../../../../../../ \
  ${PACKAGE_DIR}/GIMP.app/Contents/Resources/Library/Frameworks/Python.framework/Versions/3.10/Resources/Python.app/Contents/MacOS/Python
install_name_tool -add_rpath @loader_path/../../../../../ \
  ${PACKAGE_DIR}/GIMP.app/Contents/Resources/Library/Frameworks/Python.framework/Versions/3.10/Python

echo "removing build path from the .gir files"
find  ${PACKAGE_DIR}/GIMP.app/Contents/Resources/share/gir-1.0/*.gir \
   -exec sed -i '' "s|${OLDPATH}||g" {} +

echo "removing previous rpath from the .gir files (in case it's there)"
find  ${PACKAGE_DIR}/GIMP.app/Contents/Resources/share/gir-1.0/*.gir \
   -exec sed -i '' "s|@rpath/||g" {} +

echo "adding @rpath to the .gir files"
find ${PACKAGE_DIR}/GIMP.app/Contents/Resources/share/gir-1.0/*.gir \
   -exec sed -i '' 's|[a-z0-9/\._-]*.dylib|@rpath/&|g' {} +

echo "generating .typelib files with @rpath"
find ${PACKAGE_DIR}/GIMP.app/Contents/Resources/share/gir-1.0/*.gir | while IFS= read -r pathname; do
    base=$(basename "$pathname")
    g-ir-compiler --includedir=${PACKAGE_DIR}/GIMP.app/Contents/Resources/share/gir-1.0 ${pathname} -o ${PACKAGE_DIR}/GIMP.app/Contents/Resources/lib/girepository-1.0/${base/.gir/.typelib}
done

echo "fixing pixmap cache"
sed -i.old 's|@executable_path/../Resources/||' \
    ${PACKAGE_DIR}/GIMP.app/Contents/Resources/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache
# Works around gdk-pixbuf loader bug for release builds only https://gitlab.gnome.org/GNOME/gdk-pixbuf/-/issues/217
mkdir -p "${PACKAGE_DIR}/GIMP.app/Contents/Resources/lib/gimp/2.99/plug-ins/Resources/lib"
pushd ${PACKAGE_DIR}/GIMP.app/Contents/Resources/lib/gimp/2.99/plug-ins/Resources/lib
  ln -s ../../../../../gdk-pixbuf-2.0 gdk-pixbuf-2.0
popd

echo "fixing IMM cache"
sed -i.old 's|@executable_path/../Resources/||' \
    ${PACKAGE_DIR}/GIMP.app/Contents/Resources/etc/gtk-3.0/gtk.immodules

if [[ "$1" == "debug" ]]; then
  echo "Generating debug symbols"
  find  ${PACKAGE_DIR}/GIMP.app/ -type f -perm +111 \
     | xargs file \
     | grep ' Mach-O '|awk -F ':' '{print $1}' \
     | xargs -n1 dsymutil
fi

echo "create missing links. should we use wrappers instead?"

pushd ${PACKAGE_DIR}/GIMP.app/Contents/MacOS
  ln -s gimp-console-2.99 gimp-console
  ln -s gimp-debug-tool-2.99 gimp-debug-tool
  ln -s python3.10 python
  ln -s python3.10 python3
popd

echo "copy xdg-email wrapper to the package"
mkdir -p ${PACKAGE_DIR}/GIMP.app/Contents/MacOS
cp xdg-email ${PACKAGE_DIR}/GIMP.app/Contents/MacOS

echo "Creating pyc files"
python3.10 -m compileall -q ${PACKAGE_DIR}/GIMP.app

echo "trimming optimized pyc from macports"
find ${PACKAGE_DIR}/GIMP.app -name '*opt-[12].pyc' -delete

echo "trimming out unused gettext files"
find -E ${PACKAGE_DIR}/GIMP.app -iregex '.*/(coreutils|git|gettext-tools|make)\.mo' -delete

echo "symlinking all the dupes"
jdupes -r -l ${PACKAGE_DIR}/GIMP.app

echo "Fix adhoc signing (M1 Macs)"
for file in $FILES
do
   error_message=$(/usr/bin/codesign -v "$file" 2>&1)
   if [[ "${error_message}" == *"invalid signature"* ]]
   then
     /usr/bin/codesign --sign - --force --preserve-metadata=entitlements,requirements,flags,runtime "$file"
   fi
done

echo "Done bundling"
