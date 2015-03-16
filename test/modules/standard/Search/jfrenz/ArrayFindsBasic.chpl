use Search;

// Things that should be tested include at least...:
//
// Search directions: First/Last
// Data does/doesn't contain the searched element.
// Search in limited range/search in whole array
// Provide/do not provide comparator function
//
// All combinations of above
// 
// Is there a need to test for other than 1-based indexing?


// Test data
// Indices of elements:
//                1  2  3  4  5  6  7  8  9  10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32
const testData = [7, 0, 0, 2, 2, 7, 3, 3, 2, 7, 0, 8, 1, 5, 2, 6, 3, 2, 8, 3, 4, 0, 2, 9, 5, 3, 3, 2, 3, 9, 8, 5];


writeln("Test data:");
writeln(testData);
writeln();

// (true, 7)
writeln(FindFirst(testData, 3));

// (true, 28)
writeln(FindLast(testData, 2));

// (true, 6)
writeln(FindFirst(testData, 7, 4..21));

// (true, 18);
writeln(FindLast(testData, 2, 4..21));

// false
writeln(FindFirst(testData, 11)(1));

// false
writeln(FindLast(testData, 11)(1));

// false
writeln(FindFirst(testData, 0, 4..9)(1));

// false
writeln(FindLast(testData, 0, 14..21)(1));


class ComparatorClass {
    proc this(a: int, b: int): bool {
        return (abs(a-b) <= 1);
    }
}

const Comparator = new ComparatorClass();



// (true, 4)
writeln(FindFirst(testData, 3, comparator=Comparator));

// (true, 31)
writeln(FindLast(testData, 7, comparator=Comparator));

// (true, 6)
writeln(FindFirst(testData, 7, 4..21, comparator=Comparator));

// (true, 21);
writeln(FindLast(testData, 5, 4..21, comparator=Comparator));

// false
writeln(FindFirst(testData, 11, comparator=Comparator)(1));

// false
writeln(FindLast(testData, 11, comparator=Comparator)(1));

// false
writeln(FindFirst(testData, 11, 4..9, comparator=Comparator)(1));

// false
writeln(FindLast(testData, 11, 14..21, comparator=Comparator)(1));
