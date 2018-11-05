# Matrix conversions.
# Dense to sparse creates a (row, column, value) stream from your data. Sparse to
# dense inverts that. You can specify where the matrix data begins using a column
# identifier; this is useful when your matrices are prefixed with keys.

sub matrix_cell_combine($$) {
  return $_[0] = $_[1] unless defined $_[0];
  $_[0] += $_[1];
}

defoperator dense_to_sparse => q{
  my ($col) = @_;
  $col ||= 0;
  my @q;
  my $n = 0;
  while (defined($_ = @q ? shift @q : <STDIN>)) {
    chomp(my @fs = split /\t/);
    if ($col) {
      $n = 0;
      my $k  = join "\t", @fs[0..$col-1];
      my $kr = qr/\Q$k\E/;
      print join("\t", $k, $n, $_ - $col, $fs[$_]), "\n" for $col..$#fs;
      my $l;
      while (defined($l = <STDIN>) && $l =~ /^$kr\t/) {
        ++$n;
        chomp(@fs = split /\t/, $l);
        print join("\t", $k, $n, $_ - $col, $fs[$_]), "\n" for $col..$#fs;
      }
      push @q, $l if defined $l;
    } else {
      print join("\t", $n, $_, $fs[$_]), "\n" for 0..$#fs;
      ++$n;
    }
  }
};

defoperator sparse_to_dense => q{
  my ($col) = @_;
  $col ||= 0;
  my $n = 0;
  my @q;
  my $row = -1;
  while (defined($_ = @q ? shift @q : <STDIN>)) {
    ++$row;
    chomp;
    my @r = split /\t/, $_, $col + 3;
    my $k = join "\t", @r[0..$col];
    my $kr = qr/\Q$k\E/;
    my @fs = $col ? @r[0..$col-1] : ();
    if ($col < @r) {
      no warnings 'numeric';
      ++$row, print "\n" until $row >= $r[$col];
    }
    matrix_cell_combine $fs[$col + $r[$col+1]], $r[$col+2];
    matrix_cell_combine $fs[$col + $1], $2
      while defined($_ = <STDIN>) && /^$kr\t([^\t]+)\t(.*)/;
    push @q, $_ if defined;
    print join("\t", map defined() ? $_ : '', @fs), "\n";
  }
};

defoperator pivot_table => q{
  my $row_id = 0;
  my $col_id = 0;
  my %row_ids;
  my %col_ids;
  my @cells;
  my @row_labels;
  my @col_labels;

  while (<STDIN>)
  {
    chomp;
    my ($row, $col, $v) = split /\t/;
    my $x = ($col_ids{$col} ||= ++$col_id) - 1;
    my $y = ($row_ids{$row} ||= ++$row_id) - 1;
    $row_labels[$y] = $row;
    $col_labels[$x] = $col;
    ${$cells[$y] ||= []}[$x] += $v;
  }

  print join("\t", "", @col_labels), "\n";
  for my $i (0..$#cells)
  {
    print join("\t", $row_labels[$i], @{$cells[$i] || []}), "\n";
  }
};

defoperator unflatten => q{
  my ($n_cols) = @_;
  my @row = ();
  while(<STDIN>) {
    chomp;
    push @row, split /\t/, $_;
    while(@row >= $n_cols) {
      my @emit_vals = splice(@row, 0, $n_cols);
      print(join("\t", @emit_vals). "\n"); 
      }
    }
  if (@row > 0) {
    while(@row > 0) {
      my @emit_vals = splice(@row, 0, $n_cols);
      print(join("\t", @emit_vals). "\n");
    }
  }
};

defoperator partial_transpose =>
q{
  my ($col) = @_;
  while (<STDIN>)
  {
    chomp;
    my @fs   = split /\t/;
    my $base = join "", map "$_\t", @fs[0..$col-1];
    print "$base$fs[$_]\n" for $col..$#fs;
  }
};

defshort '/X',  pmap q{sparse_to_dense_op $_}, popt colspec1;
defshort '/XP', pmap q{pivot_table_op}, pnone;

defshort '/Y', pmap q{dense_to_sparse_op $_}, popt colspec1;
defshort '/Z', palt pmap(q{unflatten_op 0 + $_}, integer),
                    pmap(q{partial_transpose_op $_}, colspec1);

# NumPy interop.
# Partitioned by the first row value and sent in as dense matrices.

use constant numpy_gen => gen pydent q{
  from numpy import *
  from sys   import stdin, stdout, stderr
  try:
    stdin = stdin.buffer
    stdout = stdout.buffer
  except:
    pass
  while True:
    try:
      dimensions = fromstring(stdin.read(8), dtype=">u4", count=2)
    except:
      exit()
    x = fromstring(stdin.read(8*dimensions[0]*dimensions[1]),
                   dtype="d",
                   count=dimensions[0]*dimensions[1]) \
        .reshape(dimensions)
  %body
    if type(x) != ndarray: x = array(x)
    if len(x.shape) != 2: x = reshape(x, (-1, 1))
    stdout.write(array(x.shape).astype(">u4").tostring())
    stdout.write(x.astype("d").tostring())
    stdout.flush()};

defoperator numpy_dense => q{
  my ($col, $f) = @_;
  $col ||= 0;
  my ($i, $o) = sioproc {
    exec 'python', '-c', numpy_gen->(body => indent $f, 2)
      or die "ni: failed to execute python: $!"};

  my @q;
  my ($rows, $cols);
  my $zero = pack F => 0;
  while (defined($_ = @q ? shift @q : <STDIN>)) {
    chomp;
    my @r = split /\t/;
    my $k = $col ? join("\t", @r[0..$col-1]) : '';
    $rows = 1;
    my @m = pack "F*", @r[$col..$#r];
    my $kr = qr/\Q$k\E/;
    ++$rows, push @m, pack "F*", split /\t/, $col ? substr $_, length $1 : $_
      while defined($_ = <STDIN>) and !$col || /^($kr\t)/;
    push @q, $_ if defined;

    $cols = max map length() / 8, @m;
    safewrite_exactly $i, pack NN => $rows, $cols;
    safewrite_exactly $i, length() < $cols * 8
                            ? $_ . $zero x ($cols - length() / 8)
                            : $_
      for @m;

    $_ = '';
    saferead_exactly $o, $_, 8;
    ($rows, $cols) = unpack "NN", $_;
    for my $r (1..$rows)
    {
      $_ = '';
      saferead_exactly $o, $_, $cols*8;
      print join("\t", $col ? ($k) : (), unpack "F$cols", $_), "\n";
    }
  }

  close $i;
  close $o;
  $o->await;
};

defshort '/N', pmap q{numpy_dense_op @$_}, pseq popt colspec1, pycode;
