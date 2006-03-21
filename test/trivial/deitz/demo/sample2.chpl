config var phrase : string = "shuffle me please";
const n = length(phrase);

var encoded = phrase(1..n by 2) + phrase(2..n by 2);

var decoder : seq of int;
for i:int in 1..n/2 do
  decoder = decoder # (/ i, n/2 + n % 2 + i /);
if n % 2 == 1 { 
  var tmp : int = n / 2 + 1;
  decoder = decoder # (/ tmp /);
}
var decoded : string;
for i:int in decoder do
  decoded = decoded + encoded(i);

writeln("phrase:   ", phrase);
writeln("encoded:  ", encoded);
writeln("decoder:  ", decoder);
writeln("decoded:  ", decoded);
