# ni frontend functions: option parsing and compilation
# Supporting definitions are in ni/structure.sh, and meta/ni-option.sh for the
# metaprogramming used by home/conf.

# Lambda redesign...
# NB: lambda options are deliberately delayed; that is, we don't parse them
# until the lambda is invoked because the lambda may be running within a
# context that provides different CLI arguments.
#
# This means we need to _preprocess_ lambdas into JIT contexts or functions.
#
# ... which implies that the whole way we're annotating lambdas, e.g. @[] vs
# -[], is flawed; the lambda doesn't dictate how it manipulates the stream.
#
# i.e. lambdas are a way to JIT-compile stuff. In particular, they make it
# possible to quote things more easily than using shell-quoting, particularly
# when the thing you're compiling is itself a command.
#
# Given that, it seems like lambdas should be context-specific: octave[ ... ]
# might just concatenate its string arguments, whereas ni[ ... ] parses
# normally? Really it's a way for a function to take an undetermined number of
# arguments.

# Option parsing
# Usage: ni_parse destination_var $vector_ref
#
# $vector_ref comes from using "vector" to convert "$@" to a vector object.
# ni_parse will then consume the vector, which amounts to shifting it until
# it's empty.
#
# The resulting structure is a vector of option defstructs.

ni_parse() {
  vector ni_parse_v

  while lpop ni_parse_option $2; do
    case "$ni_parse_option" in
    # Closer: done with inner parse, so return
    ']'|'}') break ;;

    # Openers: parse inside, then add to vector. Delegate to ni_bracket_case to
    # select the constructing class.
    '['|'@['|'-['|'-@['|'{'|'@{'|'-{'|'-@{')
      ni_bracket_case ni_parse_b "$ni_parse_option"
      set -- "$1" "$2" "$ni_parse_b" "$ni_parse_v"
      ni_parse ni_parse_xs $2
      $3 ni_parse_obj $ni_parse_xs
      ni_parse_v=$4
      rpush $ni_parse_v $ni_parse_obj
      ;;

    # Long options
    --*)
      set -- "$1" "$2" "$ni_parse_v"
      ni_parse_long ni_parse_obj ${ni_parse_option#--} $2
      ni_parse_v=$3
      rpush $ni_parse_v $ni_parse_obj
      ;;

    # Short options
    -*|^*|@^*)
      # Some explanation here. ni_parse is about establishing the context of an
      # argument, which is why we match so many cases for this branch.
      # ni_parse_short_options sorts out the lambda-notation for us by wrapping
      # the results (and intermediate ones; see doc/operators.md for some
      # examples of this). All we need to do is trim the leading -, if there is
      # one, from the option string so it sees exactly what it needs to.

      set -- "$1" "$2" "$ni_parse_v"
      ni_parse_short ni_parse_objs ${ni_parse_option#-} $2
      ni_parse_v=$3
      rappend $ni_parse_v $ni_parse_objs
      ;;

    # Quasifiles
    *)
      quasifile ni_parse_obj "$ni_parse_option"
      rpush $ni_parse_v $ni_parse_obj
      ;;
    esac
  done

  eval "$1=\$ni_parse_v"
}

ni_bracket_case() {
  case "$2" in
  '[')   eval "$1=lambda"     ;;
  '@[')  eval "$1=lambdafork" ;;
  '-[')  eval "$1=lambdaplus" ;;
  '-@[') eval "$1=lambdamix"  ;;
  '{')   eval "$1=branch"     ;;
  '@{')  eval "$1=branchfork" ;;
  '-{')  eval "$1=branchsub"  ;;
  '-@{') eval "$1=branchmix"  ;;
  esac
}

# Takes a constructor, a syntax string, and a vector of CLI options, and
# returns the constructed option after shifting the vector. Parses any lambdas
# it encounters, which is why this function contains recursion-safety.
ni_syntax_long() {
  ni_syntax_long_p=$1
  while [ -n "$ni_syntax_long_p" ]; do
    substr ni_syntax_long_n "$ni_syntax_long_p" 0 1
    substr ni_syntax_long_p "$ni_syntax_long_p" 1

    nth ni_syntax_long_arg "$2" 0

    case "$ni_syntax_long_n" in
    s)
    esac
  done
}

# Constructs the parse tree for a long option and its arguments, shifting the
# CLI-option vector to point to the following operator.
#
# Usage: ni_parse_long dest_var $long_option_name $cli_vector
ni_parse_long() {
  get ni_parse_long_op $long_options $2
  syntax ni_parse_long_syn $ni_parse_long_op

  TODO ni_parse_long
}

# Constructs a vector of parsed short-option defstructs (with arguments),
# shifting the CLI vector accordingly. This function will always consume an
# exact number of elements; i.e. even though a short option may not itself
# represent an entire command-line argument, this function will continue
# parsing options until it reaches the end of the string.
#
# Usage: ni_parse_short dest_var $short_option $cli_vector
ni_parse_short() {
  TODO ni_parse_short
}

# Compiles a structure produced by ni_parse, returning a jit context to execute
# it. The jit context can be executed without arguments or environment
# variables, since all quasifiles and other data will be included.
#
# Usage: ni_compile dest_var $parsed_vector
ni_compile() {
  TODO ni_compile
}