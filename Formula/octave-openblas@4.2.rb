# Octave 4.2, built against OpenBLAS instead of Apple's vecLib

class MacTeXRequirement < Requirement
  fatal true

  satisfy(:build_env => false) {
    Pathname.new("/Library/TeX/texbin/latex").executable?
  }

  def message; <<~EOS
    MacTeX must be installed in order to build --with-docs.
  EOS
  end
end


class OctaveOpenblasAT42 < Formula
  desc "High-level interpreted language for numerical computing"
  homepage "https://www.gnu.org/software/octave/index.html"
  url "https://ftp.gnu.org/gnu/octave/octave-4.2.1.tar.gz"
  mirror "https://ftpmirror.gnu.org/octave/octave-4.2.1.tar.gz"
  sha256 "80c28f6398576b50faca0e602defb9598d6f7308b0903724442c2a35a605333b"

  keg_only "so it can be installed alongside the default non-openblas version"

  option "without-docs", "Skip documentation (requires MacTeX)"
  option "without-test", "Skip compile-time make checks (Not Recommended)"

  # Complete list of dependencies at https://wiki.octave.org/Building
  depends_on "automake" => :build
  depends_on "autoconf" => :build
  depends_on "gnu-sed" => :build # https://lists.gnu.org/archive/html/octave-maintainers/2016-09/msg00193.html
  depends_on "pkg-config" => :build
  depends_on "arpack-openblas"
  depends_on "epstool"
  depends_on "fftw"
  depends_on "fig2dev"
  depends_on "fontconfig"
  depends_on "freetype"
  depends_on "ghostscript"
  depends_on "gl2ps"
  depends_on "glpk"
  depends_on "gnuplot"
  depends_on "graphicsmagick"
  depends_on "hdf5"
  depends_on "libsndfile"
  depends_on "libtool"
  depends_on "openblas"
  depends_on "pcre"
  depends_on "portaudio"
  depends_on "pstoedit"
  depends_on "qhull"
  depends_on "qrupdate-openblas"
  depends_on "readline"
  depends_on "suite-sparse-openblas"
  depends_on "texinfo" # http://lists.gnu.org/archive/html/octave-maintainers/2018-01/msg00016.html
  depends_on :java => ["1.8+", :recommended]
  depends_on MacTeXRequirement if build.with?("docs")

  # Dependencies use Fortran, leading to spurious messages about GCC
  cxxstdlib_check :skip

  def install
    # Hack: munge HG-ID to reflect that we're adding patches
    hg_id = `cat HG-ID`.chomp;
    File.delete("HG-ID");
    Pathname.new("HG-ID").write "#{hg_id} + patches\n"

    # Remove inline keyword on file_stat destructor which breaks macOS
    # compilation (bug #50234).
    # Upstream commit from 24 Feb 2017 https://hg.savannah.gnu.org/hgweb/octave/rev/a6e4157694ef
    inreplace "liboctave/system/file-stat.cc",
      "inline file_stat::~file_stat () { }", "file_stat::~file_stat () { }"
    inreplace "scripts/java/module.mk",
      "-source 1.3 -target 1.3", ""
    # allow for Oracle Java (>=1.8) without requiring the old Apple Java 1.6
    # this is more or less the same as in https://savannah.gnu.org/patch/index.php?9439
    inreplace "libinterp/octave-value/ov-java.cc",
     "#if ! defined (__APPLE__) && ! defined (__MACH__)", "#if 1" # treat mac's java like others
    inreplace "configure.ac",
     "-framework JavaVM", "" # remove framework JavaVM as it requires Java 1.6 after build

    # Default configuration passes all linker flags to mkoctfile, to be
    # inserted into every oct/mex build. This is unnecessary and can cause
    # cause linking problems.
    inreplace "src/mkoctfile.in.cc", /%OCTAVE_CONF_OCT(AVE)?_LINK_(DEPS|OPTS)%/, '""'

    args = %W[
      --prefix=#{prefix}
      --disable-dependency-tracking
      --disable-silent-rules
      --enable-link-all-dependencies
      --enable-shared
      --disable-static
      --without-fltk
      --without-osmesa
      --with-hdf5-includedir=#{Formula["hdf5"].opt_include}
      --with-hdf5-libdir=#{Formula["hdf5"].opt_lib}
      --with-x=no
      --with-blas=-L#{Formula["openblas"].opt_lib}\ -lopenblas
      --with-portaudio
      --with-sndfile
      --without-qt
    ]

    args << "--disable-java" if build.without? "java"

    if build.without? "docs"
      args << "--disable-docs"
    else
      ENV.prepend_path "PATH", "/Library/TeX/texbin/"
    end

    # fix aclocal version issue
    system "autoreconf", "-f", "-i"
    system "./configure", *args
    system "make", "all"

    if build.with? "test"
      system "make check 2>&1 | tee \"test/make-check.log\""
      # check if all tests have passed (FAIL 0)
      results = File.readlines "test/make-check.log"
      matches = results.join("\n").match(/^\s*(FAIL)\s*0/i)
      if matches.nil?
        opoo "Some tests failed. Details are given in #{opt_prefix}/make-check.log."
      end
      # install test results
      prefix.install "test/fntests.log"
      prefix.install "test/make-check.log"
    end

    # make sure that Octave uses the modern texinfo
    rcfile = buildpath/"scripts/startup/site-rcfile"
    rcfile.append_lines "makeinfo_program(\"#{Formula["texinfo"].opt_bin}/makeinfo\");"

    system "make", "install"
  end

  test do
    system bin/"octave", "--eval", "(22/7 - pi)/pi"
    # This is supposed to crash octave if there is a problem with veclibfort
    system bin/"octave", "--eval", "single ([1+i 2+i 3+i]) * single ([ 4+i ; 5+i ; 6+i])"
    # Test java bindings: check if javaclasspath is working, return error if not
    system bin/"octave", "--eval", "try; javaclasspath; catch; quit(1); end;" if build.with? "java"
  end
end
