fun foo(a) {
  writeln("in foo, a is ", a);
  bar(7);
}

fun bar(a) {
  writeln("in bar, a is ", a);
}

foo(3);
bar(5);

