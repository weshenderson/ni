# Bootstrap concatenative interpreter
#
# Semantics:
# Numbers and strings are self-quoting; symbols prefixed with ' are
# self-quoting, otherwise they resolve+evaluate when executed. Lists, arrays,
# and hashes are all self-quoting. All values appear to be immutable and all
# functions appear to be pure.
#
# Continuations are available and encoded using values that can be converted to
# and from 3-arrays. As in Scheme, invoking a continuation causes it to replace
# the current default one. Also as in Scheme, tail recursion is required;
# although continuations have structured views of the return stack, the return
# stack will never contain an empty list.
#
# TODO: does concurrency require any type of special form, or can the
#       interpreter always use dataflow graph solving to figure it out?

package nb;

{ package nb::val; use overload qw/ "" str / }

push @nb::string::ISA, qw/ nb::val nb::one  nb::stable /;
push @nb::number::ISA, qw/ nb::val nb::one  nb::stable /;
push @nb::symbol::ISA, qw/ nb::val nb::one             /;
push @nb::list::ISA,   qw/ nb::val nb::many nb::stable /;
push @nb::array::ISA,  qw/ nb::val nb::many nb::stable /;
push @nb::hash::ISA,   qw/ nb::val nb::many nb::stable /;

sub nb::list::delimiters  { '(', ')' }
sub nb::array::delimiters { '[', ']' }
sub nb::hash::delimiters  { '{', '}' }

sub nb::string::str { "\"${$_[0]}\"" }
sub nb::one::str    { ${$_[0]} }
sub nb::many::str {
  my ($self) = @_;
  my ($open, $close) = $self->delimiters;
  $open . join(' ', $self->seq) . $close;
}

sub nb::many::seq { @{$_[0]} }
sub nb::list::seq {
  my @result;
  for (my ($self) = @_; @$self; $self = $$self[1]) {
    push @result, $$self[0];
  }
  @result;
}

sub nb::list::get {
  my ($self, $n) = @_;
  $self = $self->tail while $n-- > 0;
  $self->head;
}

sub string { my ($x) = @_; bless \$x, 'nb::string' }
sub number { my ($x) = @_;
             $x = hex $x if $x =~ /^0x/;
             bless \$x, 'nb::number' }
sub symbol { my ($x) = @_; bless \$x, 'nb::symbol' }
sub list   { @_ ? bless [$_[0], list(@_[1..$#_])], 'nb::list'
                : bless [], 'nb::list' }
sub array  { bless [@_], 'nb::array' }
sub hash   { bless [@_], 'nb::hash'  }

our %bracket_types = ( ')' => \&list,
                       ']' => \&array,
                       '}' => \&hash );

sub parse {
  local $_;
  my @stack = [];
  while ($_[0] =~ /\G (?: (?<comment> \#[!\s].*)
                        | (?<ws>      [,\s]+)
                        | (?<string>  "(?:[^\\"]|\\.)*":?)
                        | (?<number>  [-+]?[0-9][-+0-9a-zA-Z]*)
                        | (?<symbol>  '*[^"()\[\]{}\s,]+)
                        | (?<opener>  [(\[{])
                        | (?<closer>  [)\]}]))/gx) {
    my $k = (keys %+)[0];
    next if $k eq 'comment' || $k eq 'ws';
    if ($k eq 'opener') {
      push @stack, [];
    } elsif ($k eq 'closer') {
      my $last = pop @stack;
      die "too many closing brackets" unless @stack;
      push @{$stack[-1]}, $bracket_types{$+{closer}}->(@$last);
    } else {
      push @{$stack[-1]}, &{"nb::$k"}($+{$k});
    }
  }
  die "unbalanced brackets: " . scalar(@stack) . " != 1" unless @stack == 1;
  list @{$stack[0]};
}

our $nil = list;
sub cons { bless [$_[0], $_[1]], 'nb::list' }
sub nb::list::head { ${$_[0]}[0] // $nil }
sub nb::list::tail { ${$_[0]}[1] // $nil }

sub nb::list::nonempty {  scalar @{$_[0]} }
sub nb::list::empty    { !scalar @{$_[0]} }

sub nb::hash::get {
  my ($self, $k, $not_found) = @_;
  my $k_str = $k->str;
  for (my $i = $#{$self} - 1; $i >= 0; $i -= 2) {
    return $$self[$i + 1] if $$self[$i]->str eq $k_str;
  }
  $not_found;
}

sub nb::hash::contains {
  my ($self, $k) = @_;
  my $k_str = $k->str;
  for (my $i = 0; $i < @$self; $i += 2) {
    return 1 if $$self[$i]->str eq $k_str;
  }
  0;
}

sub nb::hash::assoc {
  my ($self, @kvs) = @_;
  nb::hash(@$self, @kvs);
}

sub nb::hash::dissoc {
  my ($self, @ks) = @_;
  my %ks;
  ++$ks{$_->str} for @ks;
  my @ys;
  for (my $i = 0; $i < @$self; $i += 2) {
    push @ys, $$self[$i], $$self[$i + 1] unless $ks{$$self[$i]->str};
  }
  nb::hash(@ys);
}

sub nb::list::perl_get {
  my ($self, $n) = @_;
  my @head;
  for (; @head < $n; $self = $self->tail) {
    push @head, $self->head;
  }
  ($self, @head);
}

# Interpreter logic
# The calling convention for each element is like this:
#
# (data_stack, return_stack, symbol_resolver) =
#   $x->call(data_stack, return_stack, symbol_resolver)
#
# The return stack is a list of list tails, each behaving as a local
# continuation for that computation. This is a little nicer than applicative
# CPS because functions are at liberty to inspect their continuations.
#
# Like in Joy, symbols resolve + execute themselves and lists quote themselves.
# We also have arrays and maps, which also quote themselves.

sub nb::val::invoke {
  my ($self, $ds, $rs, $r) = @_;
  (cons($self, $ds), $rs, $r);
}

sub nb::symbol::invoke {
  my ($self, $ds, $rs, $r) = @_;
  if ($$self =~ /^'(.*)$/) {
    (cons(symbol($1), $ds), $rs, $r);
  } else {
    my ($ds1, $rs1, $r1) = $r->eval(cons($self, $ds), $rs, $r);
    my ($ds2, $resolved) = $ds1->perl_get(1);

    my @result = eval { $resolved->eval($ds2, $rs1, $r1) };
    die "failed to invoke $self: $@" if $@;
    @result;
  }
}

sub nb::val::eval {
  die "argument to eval must be a list or hash (got $_[0])";
}

sub nb::list::eval {
  my ($self, $ds, $rs, $r) = @_;
  ($ds, cons($self, $rs), $r);
}

# This is the mechanism we use to implement symbol resolution.
sub nb::hash::eval {
  my ($self, $ds, $rs, $r) = @_;
  (cons($self->get($ds->head, $nil), $ds->tail), $rs, $r);
}

sub nb::perlfn::eval {
  my ($self, @xs) = @_;
  &$$self(@xs);
}

# Trampolining interpreter
sub run {
  my ($ds, $form, $resolver) = @_;
  my $rs = cons($form, $nil);
  while ($rs->nonempty) {
    my $rc = $nil;
    ($rc, $rs) = ($rs->head, $rs->tail) until $rc->nonempty || $rs->empty;
    last if $rc->empty;
    my ($next, $c) = ($rc->head, $rc->tail);
    $rs = cons($c, $rs);
    eval {
      ($ds, $rs, $resolver) = $next->invoke($ds, $rs, $resolver);
    };
    die "error invoking $next: $@\nds = $ds\nrs = $rs\nres = $resolver" if $@;
  }
  ($ds, $resolver);
}

# Initial symbol resolver and global functions
our $resolver = nb::hash;

sub def {
  my ($name, $f) = @_;
  $resolver = $resolver->assoc(symbol($name), bless \$f, 'nb::perlfn');
}

sub defn {
  # Define a regular function without any particularly magical stuff.
  my ($name, $arity, $f) = @_;
  die "defn usage: name, arity, fn" unless @_ == 3;
  def $name, sub {
    my ($ds, $rs, $r) = @_;
    my ($ds_, @xs) = $ds->perl_get($arity);
    my @r = &$f(@xs);
    $ds_ = cons(pop(@r), $ds_) while @r;
    ($ds_, $rs, $r);
  };
}

defn $_, 2, eval "sub { number(\${\$_[0]} $_ \${\$_[1]}) }"
  for qw# + - * / % << >> & | ^ < > <= >= #;

defn $_, 1, eval "sub { number($_\${\$_[0]}) }" for qw# ! ~ #;
defn 'neg', 1, sub { number(-${$_[0]}) };

# Generic stack-manipulation command
# Takes a base-62 symbol, interpreting the first digit as the drop count and
# remaining ones as stack selectors. For example:
#
# '000          # dup
# '1            # drop
# '201          # swap

our $b62 = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
def 'st', sub {
  my ($ds, $rs, $r) = @_;
  my ($rest, $s) = $ds->perl_get(1);
  my ($base)     = $rest->perl_get(index $b62, substr($$s, 0, 1));
  my $result     = $base;

  $result = cons $rest->get($_), $result
    for map index($b62, $_), split //, substr $$s, 1;

  ($result, $rs, $r);
};

def 'nth', sub {
  my ($ds, $rs, $r) = @_;
  my ($ds_, $n) = $ds->perl_get(1);
  (cons($ds_->get($$n), $ds), $rs, $r);
};

defn 'assoc',  3, sub { $_[0]->assoc(@_[1, 2]) };
defn 'dissoc', 2, sub { $_[0]->dissoc($_[1]) };
defn 'get',    2, sub { $_[0]->get($_[1], $nil) };
defn 'get-or', 3, sub { $_[0]->get(@_[1, 2]) };
defn 'has?',   2, sub { number($_[0]->contains($_[1])) };
defn 'nil?',   1, sub { number($_[0]->empty) };
defn 'type',   1, sub { ref($_[0]) =~ s/^ni:://r };

defn 'la', 1, sub { array($_[0]->seq) };
defn 'al', 1, sub { list($_[0]->seq) };
defn 'lh', 1, sub { hash($_[0]->seq) };
defn 'hl', 1, sub { list($_[0]->seq) };

defn '=',  2, sub { number($_[0]->str eq $_[1]->str) };
defn '!=', 2, sub { number($_[0]->str ne $_[1]->str) };

defn 'str',  1, sub { string($_[0]->str) };
defn 'read', 1, sub { parse(${$_[0]})->head };

defn 'cons',   2, \&cons;
defn 'uncons', 1, sub { ($_[0]->head, $_[0]->tail) };

def 'getr', sub {
  my ($ds, $rs, $r) = @_;
  (cons($r, $ds), $rs, $r);
};

def 'setr', sub {
  my ($ds, $rs, $r) = @_;
  ($ds->tail, $rs, $ds->head);
};

def 'eval', sub {
  my ($ds, $rs, $r) = @_;
  ($ds->tail, cons($ds->head, $rs), $r);
};

def 'eval/cc', sub {
  my ($ds, $rs, $r) = @_;
  my $cc = array($ds->tail, $rs, $r);
  (cons($cc, $ds->tail), cons($ds->head, $rs), $r);
};

def 'setcc', sub {
  my ($ds, $rs, $r) = @_;
  my $c = $ds->head;
  die "continuation argument to set/cc must be an array (got $c)"
    unless ref($c) eq 'nb::array';
  die "continuation argument (@$c) must have exactly three elements"
    unless @$c == 3;
  @$c;
};

# Interpreter runtime
our $ds = $nil;
if (@ARGV) {
  my $input   = join '', <>;
  my $initial = eval {parse $input};
  die "$@ when parsing $input" if $@;
  ($ds, $resolver) = eval {run $ds, $initial, $resolver};
  die "$@ when running $initial" if $@;
}

if (-t STDIN) {
  select((select(STDERR), $|++)[0]);
  print STDERR "> ";
  while (<STDIN>) {
    eval {
      my $parsed = parse $_;
      ($ds, $resolver) = run $ds, $parsed, $resolver;
      my $ds_ = $ds;
      for (; $ds_->nonempty; $ds_ = $ds_->tail) {
        print STDERR "= " . $ds_->head->str, "\n";
      }
    };
    print STDERR "! $@" if $@;
    print STDERR "> ";
  }
}