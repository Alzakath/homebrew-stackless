
class Stackless < Formula
  desc "Interpreted, interactive, object-oriented programming language"
  homepage "http://www.stackless.com"
  url "http://www.stackless.com/binaries/stackless-2716-export.tar.xz"
  sha256 "2db64fbd47567a1c0683fba7a54387892d2299915f9848b54c450b5eb95358dc"
  head 'https://github.com/stackless-dev/stackless', :using => :git, :branch => '2.7-slp'

  # setuptools remembers the build flags python is built with and uses them to
  # build packages later. Xcode-only systems need different flags.
  pour_bottle? do
    reason <<~EOS
      The bottle needs the Apple Command Line Tools to be installed.
        You can install them, if desired, with:
          xcode-select --install
    EOS
    satisfy { MacOS::CLT.installed? }
  end

  depends_on "pkg-config" => :build
  depends_on "gdbm"
  depends_on "openssl@1.1"
  depends_on "readline"
  depends_on "sqlite"

  resource "setuptools" do
    url "https://files.pythonhosted.org/packages/11/0a/7f13ef5cd932a107cd4c0f3ebc9d831d9b78e1a0e8c98a098ca17b1d7d97/setuptools-41.6.0.zip"
    sha256 "6afa61b391dcd16cb8890ec9f66cc4015a8a31a6e1c2b4e0c464514be1a3d722"
  end

  resource "pip" do
    url "https://files.pythonhosted.org/packages/ce/ea/9b445176a65ae4ba22dce1d93e4b5fe182f953df71a145f557cffaffc1bf/pip-19.3.1.tar.gz"
    sha256 "21207d76c1031e517668898a6b46a9fb1501c7a4710ef5dfd6a40ad9e6757ea7"
  end

  resource "wheel" do
    url "https://files.pythonhosted.org/packages/59/b0/11710a598e1e148fb7cbf9220fd2a0b82c98e94efbdecb299cb25e7f0b39/wheel-0.33.6.tar.gz"
    sha256 "10c9da68765315ed98850f8e048347c3eb06dd81822dc2ab1d4fde9dc9702646"
  end

  resource "virtualenv" do
    url "https://files.pythonhosted.org/packages/e7/80/15d28e5a075fb02366ce97558120bb987868dab3600233ec7be032dc6d01/virtualenv-16.7.7.tar.gz"
    sha256 "d257bb3773e48cac60e475a19b608996c73f4d333b3ba2e4e57d5ac6134e0136"
  end

  resource "virtualenvwrapper" do
    url "https://files.pythonhosted.org/packages/c1/6b/2f05d73b2d2f2410b48b90d3783a0034c26afa534a4a95ad5f1178d61191/virtualenvwrapper-4.8.4.tar.gz"
    sha256 "51a1a934e7ed0ff221bdd91bf9d3b604d875afbb3aa2367133503fee168f5bfa"
  end

  resource "pbr" do
      url "https://files.pythonhosted.org/packages/99/f1/7807d3409c79905a907f1c616d910c921b2a8e73c17b2969930318f44777/pbr-5.4.3.tar.gz"
      sha256 "2c8e420cd4ed4cec4e7999ee47409e876af575d4c35a45840d59e8b5f3155ab8"
  end

  patch do
    url "https://raw.githubusercontent.com/Alzakath/homebrew-stackless/master/stackless-macos-10.14.patch"
    sha256 "242c11c9fa7c0dcb74d226640255bbb40f453873525a73083b1d23089008ad1d"
  end

  def lib_cellar
    prefix/"Frameworks/Python.framework/Versions/2.7/lib/python2.7"
  end

  def site_packages_cellar
    lib_cellar/"site-packages"
  end

  # The HOMEBREW_PREFIX location of site-packages.
  def site_packages
    HOMEBREW_PREFIX/"lib/python2.7/site-packages"
  end

  def install
    # Unset these so that installing pip and setuptools puts them where we want
    # and not into some other Python the user has installed.
    ENV["PYTHONHOME"] = nil
    ENV["PYTHONPATH"] = nil

    args = %W[
      --prefix=#{prefix}
      --enable-ipv6
      --datarootdir=#{share}
      --datadir=#{share}
      --enable-framework=#{frameworks}
      --without-ensurepip
    ]

    # See upstream bug report from 22 Jan 2018 "Significant performance problems
    # with Python 2.7 built with clang 3.x or 4.x"
    # https://bugs.python.org/issue32616
    # https://github.com/Homebrew/homebrew-core/issues/22743
    if DevelopmentTools.clang_build_version >= 802 &&
       DevelopmentTools.clang_build_version < 902
      args << "--without-computed-gotos"
    end

    args << "--without-gcc" if ENV.compiler == :clang

    cflags   = []
    ldflags  = []
    cppflags = []

    if MacOS.sdk_path_if_needed
      # Help Python's build system (setuptools/pip) to build things on SDK-based systems
      # The setup.py looks at "-isysroot" to get the sysroot (and not at --sysroot)
      cflags  << "-isysroot #{MacOS.sdk_path}" << "-I#{MacOS.sdk_path}/usr/include"
      ldflags << "-isysroot #{MacOS.sdk_path}"
      # For the Xlib.h, Python needs this header dir with the system Tk
      # Yep, this needs the absolute path where zlib needed a path relative
      # to the SDK.
      cflags  << "-I#{MacOS.sdk_path}/System/Library/Frameworks/Tk.framework/Versions/8.5/Headers"
    end

    # Avoid linking to libgcc https://code.activestate.com/lists/python-dev/112195/
    args << "MACOSX_DEPLOYMENT_TARGET=#{MacOS.version}"

    # We want our readline and openssl! This is just to outsmart the detection code,
    # superenv handles that cc finds includes/libs!
    inreplace "setup.py" do |s|
      s.gsub! "do_readline = self.compiler.find_library_file(lib_dirs, 'readline')",
              "do_readline = '#{Formula["readline"].opt_lib}/libhistory.dylib'"
      s.gsub! "/usr/local/ssl", Formula["openssl@1.1"].opt_prefix
    end

    inreplace "setup.py" do |s|
      s.gsub! "sqlite_setup_debug = False", "sqlite_setup_debug = True"
      s.gsub! "for d_ in inc_dirs + sqlite_inc_paths:",
              "for d_ in ['#{Formula["sqlite"].opt_include}']:"

      # Allow sqlite3 module to load extensions:
      # https://docs.python.org/library/sqlite3.html#f1
      s.gsub! 'sqlite_defines.append(("SQLITE_OMIT_LOAD_EXTENSION", "1"))', ""
    end

    # Allow python modules to use ctypes.find_library to find homebrew's stuff
    # even if homebrew is not a /usr/local/lib. Try this with:
    # `brew install enchant && pip install pyenchant`
    inreplace "./Lib/ctypes/macholib/dyld.py" do |f|
      f.gsub! "DEFAULT_LIBRARY_FALLBACK = [", "DEFAULT_LIBRARY_FALLBACK = [ '#{HOMEBREW_PREFIX}/lib',"
      f.gsub! "DEFAULT_FRAMEWORK_FALLBACK = [", "DEFAULT_FRAMEWORK_FALLBACK = [ '#{HOMEBREW_PREFIX}/Frameworks',"
    end

    args << "CFLAGS=#{cflags.join(" ")}" unless cflags.empty?
    args << "LDFLAGS=#{ldflags.join(" ")}" unless ldflags.empty?
    args << "CPPFLAGS=#{cppflags.join(" ")}" unless cppflags.empty?

    system "./configure", *args
    system "make"

    ENV.deparallelize do
      # Tell Python not to install into /Applications
      system "make", "install", "PYTHONAPPSDIR=#{prefix}"
      system "make", "frameworkinstallextras", "PYTHONAPPSDIR=#{pkgshare}"
    end

    # Fixes setting Python build flags for certain software
    # See: https://github.com/Homebrew/homebrew/pull/20182
    # https://bugs.python.org/issue3588
    inreplace lib_cellar/"config/Makefile" do |s|
      s.change_make_var! "LINKFORSHARED",
        "-u _PyMac_Error $(PYTHONFRAMEWORKINSTALLDIR)/Versions/$(VERSION)/$(PYTHONFRAMEWORK)"
    end

    # Prevent third-party packages from building against fragile Cellar paths
    inreplace [lib_cellar/"_sysconfigdata.py",
               lib_cellar/"config/Makefile",
               frameworks/"Python.framework/Versions/Current/lib/pkgconfig/python-2.7.pc"],
              prefix, opt_prefix

    # Symlink the pkgconfig files into HOMEBREW_PREFIX so they're accessible.
    (lib/"pkgconfig").install_symlink Dir[frameworks/"Python.framework/Versions/Current/lib/pkgconfig/*"]

    # Remove 2to3 because Python 3 also installs it
    rm bin/"2to3"

    # Remove the site-packages that Python created in its Cellar.
    site_packages_cellar.rmtree

    (libexec/"setuptools").install resource("setuptools")
    (libexec/"pip").install resource("pip")
    (libexec/"wheel").install resource("wheel")
    (libexec/"virtualenv").install resource("virtualenv")
    (libexec/"pbr").install resource("pbr")
    (libexec/"virtualenvwrapper").install resource("virtualenvwrapper")
  end

  def post_install
    # Avoid conflicts with lingering unversioned files from Python 3
    rm_f %W[
      #{HOMEBREW_PREFIX}/bin/easy_install
      #{HOMEBREW_PREFIX}/bin/pip
      #{HOMEBREW_PREFIX}/bin/wheel
    ]

    # Fix up the site-packages so that user-installed Python software survives
    # minor updates, such as going from 2.7.0 to 2.7.1:

    # Create a site-packages in HOMEBREW_PREFIX/lib/python2.7/site-packages
    site_packages.mkpath

    # Symlink the prefix site-packages into the cellar.
    site_packages_cellar.unlink if site_packages_cellar.exist?
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
    rm_rf Dir["#{site_packages}/pip[-_.][0-9]*", "#{site_packages}/pip"]
    rm_rf Dir["#{site_packages_cellar}/virtualenv*"]
    rm_rf Dir["#{site_packages_cellar}/pbr*"]
    rm_rf Dir["#{site_packages_cellar}/virtualenvwrapper*"]

    setup_args = ["-s", "setup.py", "--no-user-cfg", "install", "--force",
                  "--verbose",
                  "--single-version-externally-managed",
                  "--record=installed.txt",
                  "--install-scripts=#{bin}",
                  "--install-lib=#{site_packages}"]

    (libexec/"setuptools").cd { system "#{bin}/python", *setup_args }
    (libexec/"pip").cd { system "#{bin}/python", *setup_args }
    (libexec/"wheel").cd { system "#{bin}/python", *setup_args }
    (libexec/"virtualenv").cd { system "#{bin}/python", *setup_args }
    (libexec/"pbr").cd { system "#{bin}/python", *setup_args }
    (libexec/"virtualenvwrapper").cd { system "#{bin}/python", *setup_args }

    # When building from source, these symlinks will not exist, since
    # post_install happens after linking.
    %w[pip pip2 pip2.7 easy_install easy_install-2.7 wheel virtualenvwrapper.sh].each do |e|
      (HOMEBREW_PREFIX/"bin").install_symlink bin/e
    end

    # Help distutils find brewed stuff when building extensions
    include_dirs = [HOMEBREW_PREFIX/"include", Formula["openssl@1.1"].opt_include,
                    Formula["sqlite"].opt_include]
    library_dirs = [HOMEBREW_PREFIX/"lib", Formula["openssl@1.1"].opt_lib,
                    Formula["sqlite"].opt_lib]

    cfg = lib_cellar/"distutils/distutils.cfg"
    cfg.atomic_write <<~EOS
      [install]
      prefix=#{HOMEBREW_PREFIX}

      [build_ext]
      include_dirs=#{include_dirs.join ":"}
      library_dirs=#{library_dirs.join ":"}
    EOS
  end

  def sitecustomize
    <<~EOS
      # This file is created by Homebrew and is executed on each python startup.
      # Don't print from here, or else python command line scripts may fail!
      # <https://docs.brew.sh/Homebrew-and-Python>
      import re
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

      # Only do this for a brewed python:
      if os.path.realpath(sys.executable).startswith('#{rack}'):
          # Shuffle /Library site-packages to the end of sys.path and reject
          # paths in /System pre-emptively (#14712)
          library_site = '/Library/Python/2.7/site-packages'
          library_packages = [p for p in sys.path if p.startswith(library_site)]
          sys.path = [p for p in sys.path if not p.startswith(library_site) and
                                             not p.startswith('/System')]
          # .pth files have already been processed so don't use addsitedir
          sys.path.extend(library_packages)

          # the Cellar site-packages is a symlink to the HOMEBREW_PREFIX
          # site_packages; prefer the shorter paths
          long_prefix = re.compile(r'#{rack}/[0-9\._abrc]+/Frameworks/Python\.framework/Versions/2\.7/lib/python2\.7/site-packages')
          sys.path = [long_prefix.sub('#{site_packages}', p) for p in sys.path]

          # LINKFORSHARED (and python-config --ldflags) return the
          # full path to the lib (yes, "Python" is actually the lib, not a
          # dir) so that third-party software does not need to add the
          # -F/#{HOMEBREW_PREFIX}/Frameworks switch.
          try:
              from _sysconfigdata import build_time_vars
              build_time_vars['LINKFORSHARED'] = '-u _PyMac_Error #{opt_prefix}/Frameworks/Python.framework/Versions/2.7/Python'
          except:
              pass  # remember: don't print here. Better to fail silently.

          # Set the sys.executable to use the opt_prefix
          sys.executable = '#{opt_bin}/python2.7'
    EOS
  end

  def caveats; <<~EOS
    Pip and setuptools have been installed. To update them
      pip install --upgrade pip setuptools

    You can install Python packages with
      pip install <package>

    They will install into the site-package directory
      #{site_packages}

    See: https://docs.brew.sh/Homebrew-and-Python
  EOS
  end

  keg_only "avoid conflicts between CPython and Stackless"

  test do
    # Check if sqlite is ok, because we build with --enable-loadable-sqlite-extensions
    # and it can occur that building sqlite silently fails if OSX's sqlite is used.
    system "#{bin}/python", "-c", "import sqlite3"
    # Check if some other modules import. Then the linked libs are working.
    system "#{bin}/python", "-c", "import Tkinter; root = Tkinter.Tk()"
    system "#{bin}/python", "-c", "import gdbm"
    system "#{bin}/python", "-c", "import zlib"
    system bin/"pip", "list", "--format=columns"
  end
end
