# Gnuplot interop.
# An operator that sends output to a gnuplot process.

BEGIN {defdsp gnuplot_code_prefixalt => 'prefixes for gnuplot code';
       defparseralias gnuplot_colspec => palt colspec1, pmap q{undef}, pstr ':'}
BEGIN {defparseralias gnuplot_code =>
         pmap q{join "", map ref($_) ? @$_ : $_, @$_},
              pseq prep('dsp/gnuplot_code_prefixalt'),
                   popt generic_code}

defoperator stream_to_gnuplot => q{
  my ($col, $command) = @_;
  exec 'gnuplot', '-e', $command unless defined $col;
  my ($k, $fh) = (undef, undef);
  while (<STDIN>) {
    chomp;
    my @fs = split /\t/, $_, $col + 2;
    my $rk = join "\t", @fs[0..$col];
    if (!defined $k or $k ne $rk) {
      if (defined $fh) {
        close $fh;
        $fh->await;
      }
      $fh = siproc {exec 'gnuplot', '-e', "KEY='$k';$command"};
      $k  = $rk;
    }
    print $fh join("\t", @fs[$col+1..$#fs]) . "\n";
  }
};

defshort '/G', pmap q{stream_to_gnuplot_op @$_},
               pseq gnuplot_colspec, gnuplot_code;

# Some convenient shorthands for gnuplot -- things like interactive plotting,
# setting up JPEG export, etc.

BEGIN {defparseralias gnuplot_terminal_size =>
         pmap q{defined $_ ? "size " . join ',', @$_ : ""},
         popt pn [0, 2], integer, prx('[x,]'), integer}

defgnuplot_code_prefixalt J  => pmap q{"set terminal jpeg $_;"}, gnuplot_terminal_size;
defgnuplot_code_prefixalt PC => pmap q{"set terminal pngcairo $_;"}, gnuplot_terminal_size;
defgnuplot_code_prefixalt P  => pmap q{"set terminal png $_;"}, gnuplot_terminal_size;

defgnuplot_code_prefixalt XP => pk "set terminal x11 persist;";
defgnuplot_code_prefixalt QP => pk "set terminal qt persist;";
defgnuplot_code_prefixalt WP => pk "set terminal wx persist;";

defgnuplot_code_prefixalt '%l' => pk 'plot "-" with lines ';
defgnuplot_code_prefixalt '%d' => pk 'plot "-" with dots ';
defgnuplot_code_prefixalt '%i' => pk 'plot "-" with impulses ';
defgnuplot_code_prefixalt '%v' => pk 'plot "-" with vectors ';

defgnuplot_code_prefixalt '%t' => pmap q{"title '$_'"}, generic_code;
defgnuplot_code_prefixalt '%u' => pmap q{"using $_"},   generic_code;

# FFMPEG movie assembly.
# You can use the companion operator `GF` to take a stream of jpeg images from a
# partitioned gnuplot process and assemble a movie. `GF` accepts shell arguments
# for ffmpeg to follow `-f image2pipe -i -`.

defshort '/GF', pmap q{sh_op "ffmpeg -f image2pipe -i - $_"}, shell_command;