#!/bin/sh -e

cd `dirname $0`

fail=0
for d in tests/*; do
  if test -d $d; then
    out=$d.out
    err=$d.err
    tmp=$(mktemp)
    ./parmatch.pl $d >$tmp.out 2>$tmp.err
    if ! diff -q $d/out.txt $tmp.out; then
      echo >&2 "$d: stdout comparison failed:"
      diff -u $d/out.txt $tmp.out
      fail=1
    fi
    if ! diff -q $d/err.txt $tmp.err; then
      echo >&2 "$d: stderr comparison failed"
      diff -u $d/err.txt $tmp.err
      fail=1
    fi
  fi
done

if test $fail = 0; then
  echo SUCCEEDED
else
  echo FAILED
fi

exit $fail
