require 'formula'

class Stackless < Formula
  homepage 'http://www.stackless.com'
  head 'http://hg.python.org/stackless', :using => :hg, :branch => '2.7-slp'
  url 'http://www.stackless.com/binaries/stackless-276r3-export.tar.bz2'
  md5 '901d848df1618111f757ed39799eb870'

  option :universal
  option 'quicktest', "Run `make quicktest` after the build (for devs; may fail)"
  option 'with-brewed-tk', "Use Homebrew's Tk (has optional Cocoa and threads support)"
  option 'with-poll', "Enable select.poll, which is not fully implemented on OS X (http://bugs.python.org/issue5154)"
  option 'with-dtrace', "Experimental DTrace support (http://bugs.python.org/issue13405)"

  depends_on 'pkg-config' => :build
  depends_on 'readline' => :recommended
  depends_on 'sqlite' => :recommended
  depends_on 'gdbm' => :recommended
  depends_on 'openssl'
  depends_on 'homebrew/dupes/tcl-tk' if build.with? 'brewed-tk'
  depends_on :x11 if build.with? 'brewed-tk' and Tab.for_name('tcl-tk').used_options.include?('with-x11')

  skip_clean 'bin/pip-slp', 'bin/pip-2.7-slp'
  skip_clean 'bin/easy_install-slp', 'bin/easy_install-2.7-slp'

  resource 'setuptools' do
    url 'https://pypi.python.org/packages/source/s/setuptools/setuptools-2.2.tar.gz'
    sha1 '547eff11ea46613e8a9ba5b12a89c1010ecc4e51'
  end

  resource 'pip' do
    url 'https://pypi.python.org/packages/source/p/pip/pip-1.5.4.tar.gz'
    sha1 '35ccb7430356186cf253615b70f8ee580610f734'
  end

  # Backported security fix for CVE-2014-1912: http://bugs.python.org/issue20246
  # patch :p0 do
  #   url "https://gist.githubusercontent.com/leepa/9351856/raw/7f9130077fd760fcf9a25f50b69d9c77b155fbc5/CVE-2014-1912.patch"
  #   sha1 "db25abc381f62e9f501ad56aaa2537e48e1b0889"
  # end

  # Patch to disable the search for Tk.framework, since Homebrew's Tk is
  # a plain unix build. Remove `-lX11`, too because our Tk is "AquaTk".
  patch :DATA if build.with? "brewed-tk"

  def lib_cellar
    prefix/"Frameworks/Python.framework/Versions/2.7-slp/lib/python2.7"
  end

  def site_packages_cellar
    lib_cellar/"site-packages"
  end

  # The HOMEBREW_PREFIX location of site-packages.
  def site_packages
    HOMEBREW_PREFIX/"lib/python2.7-slp/site-packages"
  end

  def install
    opoo 'The given option --with-poll enables a somewhat broken poll() on OS X (http://bugs.python.org/issue5154).' if build.with? 'poll'

    # Unset these so that installing pip and setuptools puts them where we want
    # and not into some other Python the user has installed.
    ENV['PYTHONHOME'] = nil
    ENV['PYTHONPATH'] = nil

    args = %W[
             --prefix=#{prefix}
             --enable-ipv6
             --datarootdir=#{share}
             --datadir=#{share}
             --enable-framework=#{frameworks}
           ]

    args << '--without-gcc' if ENV.compiler == :clang
    args << '--with-dtrace' if build.with? 'dtrace'

    if superenv?
      distutils_fix_superenv(args)
    else
      distutils_fix_stdenv
    end

    if build.universal?
      ENV.universal_binary
      args << "--enable-universalsdk=/" << "--with-universal-archs=intel"
    end

    # Allow sqlite3 module to load extensions: http://docs.python.org/library/sqlite3.html#f1
    inreplace("setup.py", 'sqlite_defines.append(("SQLITE_OMIT_LOAD_EXTENSION", "1"))', '') if build.with? 'sqlite'

    # Allow python modules to use ctypes.find_library to find homebrew's stuff
    # even if homebrew is not a /usr/local/lib. Try this with:
    # `brew install enchant && pip install pyenchant`
    inreplace "./Lib/ctypes/macholib/dyld.py" do |f|
      f.gsub! 'DEFAULT_LIBRARY_FALLBACK = [', "DEFAULT_LIBRARY_FALLBACK = [ '#{HOMEBREW_PREFIX}/lib',"
      f.gsub! 'DEFAULT_FRAMEWORK_FALLBACK = [', "DEFAULT_FRAMEWORK_FALLBACK = [ '#{HOMEBREW_PREFIX}/Frameworks',"
    end

    if build.with? 'brewed-tk'
      tcl_tk = Formula["tcl-tk"].opt_prefix
      ENV.append 'CPPFLAGS', "-I#{tcl_tk}/include"
      ENV.append 'LDFLAGS', "-L#{tcl_tk}/lib"
    end

    system "./configure", *args

    # HAVE_POLL is "broken" on OS X
    # See: http://trac.macports.org/ticket/18376 and http://bugs.python.org/issue5154
    inreplace 'pyconfig.h', /.*?(HAVE_POLL[_A-Z]*).*/, '#undef \1' if build.without? "poll"

    system "make"

    ENV.deparallelize # Installs must be serialized
    # Tell Python not to install into /Applications (default for framework builds)
    system "make", "install", "PYTHONAPPSDIR=#{prefix}"
    # Demos and Tools
    system "make", "frameworkinstallextras", "PYTHONAPPSDIR=#{share}/python"
    system "make", "quicktest" if build.include? 'quicktest'

    # Post-install, fix up the site-packages so that user-installed Python
    # software survives minor updates, such as going from 2.7.0 to 2.7.1:

    # Remove the site-packages that Python created in its Cellar.
    site_packages_cellar.rmtree
    # Create a site-packages in HOMEBREW_PREFIX/lib/python2.7/site-packages
    site_packages.mkpath
    # Symlink the prefix site-packages into the cellar.
    site_packages_cellar.parent.install_symlink site_packages

    # Write our sitecustomize.py
    rm_rf Dir["#{site_packages}/sitecustomize.py[co]"]
    (site_packages/"sitecustomize.py").atomic_write(sitecustomize)

    # Remove old setuptools installations that may still fly around and be
    # listed in the easy_install.pth. This can break setuptools build with
    # zipimport.ZipImportError: bad local file header
    # setuptools-0.9.5-py3.3.egg
    rm_rf Dir["#{site_packages}/setuptools*"]
    rm_rf Dir["#{site_packages}/distribute*"]

    setup_args = [ "-s", "setup.py", "--no-user-cfg", "install", "--force", "--verbose",
                   "--install-scripts=#{bin}", "--install-lib=#{site_packages}" ]

    resource('setuptools').stage { system "#{bin}/python-slp", *setup_args }
    resource('pip').stage { system "#{bin}/python-slp", *setup_args }

    # And now we write the distutils.cfg
    cfg = lib_cellar/"distutils/distutils.cfg"
    cfg.delete if cfg.exist?
    cfg.write <<-EOF.undent
      [global]
      verbose=1
      [install]
      force=1
      prefix=#{HOMEBREW_PREFIX}
    EOF

    # Fixes setting Python build flags for certain software
    # See: https://github.com/Homebrew/homebrew/pull/20182
    # http://bugs.python.org/issue3588
    inreplace lib_cellar/"config/Makefile" do |s|
      s.change_make_var! "LINKFORSHARED",
        "-u _PyMac_Error $(PYTHONFRAMEWORKINSTALLDIR)/Versions/$(VERSION)/$(PYTHONFRAMEWORK)"
    end
  end

  def distutils_fix_superenv(args)
    # This is not for building python itself but to allow Python's build tools
    # (pip) to find brewed stuff when installing python packages.
    sqlite = Formula["sqlite"].opt_prefix
    cflags = "CFLAGS=-I#{HOMEBREW_PREFIX}/include -I#{sqlite}/include"
    ldflags = "LDFLAGS=-L#{HOMEBREW_PREFIX}/lib -L#{sqlite}/lib"
    if build.with? 'brewed-tk'
      tcl_tk = Formula["tcl-tk"].opt_prefix
      cflags += " -I#{tcl_tk}/include"
      ldflags += " -L#{tcl_tk}/lib"
    end
    unless MacOS::CLT.installed?
      # Help Python's build system (setuptools/pip) to build things on Xcode-only systems
      # The setup.py looks at "-isysroot" to get the sysroot (and not at --sysroot)
      cflags += " -isysroot #{MacOS.sdk_path}"
      ldflags += " -isysroot #{MacOS.sdk_path}"
      # Same zlib.h-not-found-bug as in env :std (see below)
      args << "CPPFLAGS=-I#{MacOS.sdk_path}/usr/include"
      # For the Xlib.h, Python needs this header dir with the system Tk
      if build.without? 'brewed-tk'
        cflags += " -I#{MacOS.sdk_path}/System/Library/Frameworks/Tk.framework/Versions/8.5/Headers"
      end
    end
    args << cflags
    args << ldflags
    # Avoid linking to libgcc http://code.activestate.com/lists/python-dev/112195/
    args << "MACOSX_DEPLOYMENT_TARGET=#{MacOS.version}"
    # We want our readline! This is just to outsmart the detection code,
    # superenv handles that cc finds includes/libs!
    inreplace "setup.py",
              "do_readline = self.compiler.find_library_file(lib_dirs, 'readline')",
              "do_readline = '#{HOMEBREW_PREFIX}/opt/readline/lib/libhistory.dylib'"
  end

  def distutils_fix_stdenv
    # Python scans all "-I" dirs but not "-isysroot", so we add
    # the needed includes with "-I" here to avoid this err:
    #     building dbm using ndbm
    #     error: /usr/include/zlib.h: No such file or directory
    ENV.append 'CPPFLAGS', "-I#{MacOS.sdk_path}/usr/include" unless MacOS::CLT.installed?

    # Don't use optimizations other than "-Os" here, because Python's distutils
    # remembers (hint: `python-config --cflags`) and reuses them for C
    # extensions which can break software (such as scipy 0.11 fails when
    # "-msse4" is present.)
    ENV.minimal_optimization

    # We need to enable warnings because the configure.in uses -Werror to detect
    # "whether gcc supports ParseTuple" (https://github.com/Homebrew/homebrew/issues/12194)
    ENV.enable_warnings
    if ENV.compiler == :clang
      # http://docs.python.org/devguide/setup.html#id8 suggests to disable some Warnings.
      ENV.append_to_cflags '-Wno-unused-value'
      ENV.append_to_cflags '-Wno-empty-body'
      ENV.append_to_cflags '-Qunused-arguments'
    end
  end

  def sitecustomize
    <<-EOF.undent
      # This file is created by Homebrew and is executed on each python startup.
      # Don't print from here, or else python command line scripts may fail!
      # <https://github.com/Homebrew/homebrew/wiki/Homebrew-and-Python>
      import os
      import sys

      if sys.version_info[0] != 2:
          # This can only happen if the user has set the PYTHONPATH for 3.x and run Python 2.x or vice versa.
          # Every Python looks at the PYTHONPATH variable and we can't fix it here in sitecustomize.py,
          # because the PYTHONPATH is evaluated after the sitecustomize.py. Many modules (e.g. PyQt4) are
          # built only for a specific version of Python and will fail with cryptic error messages.
          # In the end this means: Don't set the PYTHONPATH permanently if you use different Python versions.
          exit('Your PYTHONPATH points to a site-packages dir for Python 2.x but you are running Python ' +
               str(sys.version_info[0]) + '.x!\\n     PYTHONPATH is currently: "' + str(os.environ['PYTHONPATH']) + '"\\n' +
               '     You should `unset PYTHONPATH` to fix this.')
      else:
          # Only do this for a brewed python:
          opt_executable = '#{opt_bin}/python2.7-slp'
          if os.path.commonprefix([os.path.realpath(e) for e in [opt_executable, sys.executable]]).startswith('#{rack}'):
              # Remove /System site-packages, and the Cellar site-packages
              # which we moved to lib/pythonX.Y/site-packages. Further, remove
              # HOMEBREW_PREFIX/lib/python because we later addsitedir(...).
              sys.path = [ p for p in sys.path
                           if (not p.startswith('/System') and
                               not p.startswith('#{HOMEBREW_PREFIX}/lib/python') and
                               not (p.startswith('#{rack}') and p.endswith('site-packages'))) ]

              # LINKFORSHARED (and python-config --ldflags) return the
              # full path to the lib (yes, "Python" is actually the lib, not a
              # dir) so that third-party software does not need to add the
              # -F/#{HOMEBREW_PREFIX}/Frameworks switch.
              # Assume Framework style build (default since months in brew)
              try:
                  from _sysconfigdata import build_time_vars
                  build_time_vars['LINKFORSHARED'] = '-u _PyMac_Error #{opt_prefix}/Frameworks/Python.framework/Versions/2.7-slp/Python'
              except:
                  pass  # remember: don't print here. Better to fail silently.

              # Set the sys.executable to use the opt_prefix
              sys.executable = opt_executable

          # Tell about homebrew's site-packages location.
          # This is needed for Python to parse *.pth.
          import site
          site.addsitedir('#{site_packages}')
    EOF
  end

  def caveats; <<-EOS.undent
    Setuptools and Pip have been installed. To update them
      pip-slp install --upgrade setuptools
      pip-slp install --upgrade pip

    You can install Python packages with
      pip-slp install <package>

    They will install into the site-package directory
      #{site_packages}

    See: https://github.com/Homebrew/homebrew/wiki/Homebrew-and-Python
    EOS
  end

  test do
    # Check if sqlite is ok, because we build with --enable-loadable-sqlite-extensions
    # and it can occur that building sqlite silently fails if OSX's sqlite is used.
    system "#{bin}/python", "-c", "import sqlite3"
    # Check if some other modules import. Then the linked libs are working.
    system "#{bin}/python", "-c", "import Tkinter; root = Tkinter.Tk()"
  end
end

__END__
diff --git a/setup.py b/setup.py
index 716f08e..66114ef 100644
--- a/setup.py
+++ b/setup.py
@@ -1810,9 +1810,6 @@ class PyBuildExt(build_ext):
         # Rather than complicate the code below, detecting and building
         # AquaTk is a separate method. Only one Tkinter will be built on
         # Darwin - either AquaTk, if it is found, or X11 based Tk.
-        if (host_platform == 'darwin' and
-            self.detect_tkinter_darwin(inc_dirs, lib_dirs)):
-            return

         # Assume we haven't found any of the libraries or include files
         # The versions with dots are used on Unix, and the versions without
@@ -1858,21 +1855,6 @@ class PyBuildExt(build_ext):
             if dir not in include_dirs:
                 include_dirs.append(dir)

-        # Check for various platform-specific directories
-        if host_platform == 'sunos5':
-            include_dirs.append('/usr/openwin/include')
-            added_lib_dirs.append('/usr/openwin/lib')
-        elif os.path.exists('/usr/X11R6/include'):
-            include_dirs.append('/usr/X11R6/include')
-            added_lib_dirs.append('/usr/X11R6/lib64')
-            added_lib_dirs.append('/usr/X11R6/lib')
-        elif os.path.exists('/usr/X11R5/include'):
-            include_dirs.append('/usr/X11R5/include')
-            added_lib_dirs.append('/usr/X11R5/lib')
-        else:
-            # Assume default location for X11
-            include_dirs.append('/usr/X11/include')
-            added_lib_dirs.append('/usr/X11/lib')

         # If Cygwin, then verify that X is installed before proceeding
         if host_platform == 'cygwin':
@@ -1897,9 +1879,6 @@ class PyBuildExt(build_ext):
         if host_platform in ['aix3', 'aix4']:
             libs.append('ld')

-        # Finally, link with the X11 libraries (not appropriate on cygwin)
-        if host_platform != "cygwin":
-            libs.append('X11')

         ext = Extension('_tkinter', ['_tkinter.c', 'tkappinit.c'],
                         define_macros=[('WITH_APPINIT', 1)] + defs,