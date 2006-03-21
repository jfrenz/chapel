class C {
  var jump : int = 0;
  var result;
  var i;
}

fun next_foo(c : C) : C {
  if c.jump == 0 then
    goto _0;
  else if c.jump == 1 then
    goto _1;
label _0
  c.i = 1;
  while c.i < 5 {
    c.result = c.i;
    c.jump = 1;
    return c;
label _1
    c.i += 1;
  }
  return nil;
}

fun foo() {
  var c = C();
  var s : seq of int;
  c = next_foo(c);
  while c != nil {
    s._append_in_place(c.result);
    c = next_foo(c);
  }
  return s;
}

writeln(foo());

iterator bar() : int {
  var i = 1;
  while i < 5 {
    yield i;
    i += 1;
  }
}

writeln(bar());
