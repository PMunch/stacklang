# Stacklang - Calculator first, programming language third
Contrary to it's name stacklang is not meant to be a programming language as
such. In fact the entire project started because I wanted an easy to use RPN
based terminal calculator. However as I wanted to be able to store formulas and
define other helper functions it needed a bit of programability as well. The
design however is intended to be as easy to learn as possible, everything is
stack based, there are no special symbols you need to remember, and doing simple
calculations should always be the core focus. I've been using this calculator
now since 2019 and it's just gone through the third major rewrite to version 3.
If you're interested to learn more, let's dive into it. This README should
contain pretty much everything there is to know about this "language" but
doesn't really go into detail about how stack based programming does.

## Running Stacklang
The easiest way to run Stacklang is simply to execute the binary. This leaves
you with an interactive prompt where you can run `help` to get information about
the available commands and start playing around. You can also run Stacklang with
a list of arguments like so:
```
stacklang '100 200 +'
```
Which will output "300" in your terminal.

Another option is to pipe commands to it:
```
echo "100 200 +" | stacklang
```
or run a file with the `--script` switch:
```
stacklang --script myscript.sl
```
These can also be combined in which case scripts and command line arguments are
executed first, and then all input is evaluated. But note that there are
commands to consume input from stdin which is available to scripts if you want
to have elements on the stack before a script runs.

Stacklang will also run anything in the `custom.sl` file before doing anything
else.  This is to allow saving of your custom commands. The file must be placed
next to the binary, and will be overwritten on `exit`.

## Data types
The input to stacklang is a series of elements separated by whitespace. Each
element is evaluated as it enters the stack. There are only three data types:

- Numbers
- Strings
- Labels

Numbers and strings are just basic types which will be added to the stack and
can be acted upon by commands. Numbers can be typed as literal numbers: `42`,
`10.5`; as scientific notation `3e4`, `10e-4`; or by a literal name `pi`, `tau`,
`e`. You can also split numbers with underscores, for example as a thousands
separator `10_000`. Since this is a calculator all calculation is done with
arbitrary precision, more on this later. Strings are anything which is enclosed
in double quotes `"like this"`. You can escape double quotes in a string with a
backslash.

Labels are anything which is not quoted by double quotes, and which isn't parsed
as a number. Labels can also point to commands, if a label which points to a
command is pushed to the stack the command is executed. Commands are either
built in, or user defined. User defined commands are simply a series of
elements. Examples of built-in commands are things like `+`, `cos`, `pop`,
`xor`, `hex`, `help`, etc. As you can see most built-in commands are simple
words describing what they do. This is to make them easier to remember, no more
trying to remember which symbol meant "pop an element of the stack", it's simply
`pop`! As you might have noticed `help` is also a command, this can be used to
list out every single available command with arguments and documentation. A copy
of this information is added to the end of this README. Sometimes you need to
push a label pointing to a command onto the stack without evaluating it, this
can be done by escaping it with a backslash.

## Stack-based calculation
I've mentioned that stacklang is a stack-based RPN calculator. This means that
instead of the more common infix notation `2 + 4` it uses postfix notation `2 4
+`. While it might be unfamiliar at first it's actually a really powerful way
of performing calculations. At the heart of any RPN calculator is the stack.
Numbers are pushed onto the stack, and operations pop elements of the stack and
push the result back. Consider the above example `2 4 +`, first the `2` is
pushed onto the stack, then the `4`, then when we encounter the `+` operation
it pops the two elements off the, stack adds them together, and pushes the
result back onto the stack. Note that `+` only takes two operands. So the
"command" (in stacklang parlance) `1 2 3 +` would leave us with a stack of `1
5` since `2` and `3` have been added together and the result pushed back. The
power of this system is easier to see if we look at a slightly more complicated
example
```
(2 + 4) * (9 / 3)
```
What RPN allows us to do is break this down into parts, much like we would do
if we were to solve this in our head, or on paper. So we would first calculate
`2 4 +` leaving a `6` on the stack, then calculate `9 3 /` which would push a
`3` on the stack. Our stack now contains the two parts of the calculation `6 3`
and by applying the `*` operator we can finish our problem. This means that we
don't have to worry about entering our problem completely first, but can work
through our problem step by step and see every sub-calculation. And don't worry
if you mess up the order of elements on the stack, there are many helpful
operations that helps you mitigate this.

## Stacklang as a library
While I originally wrote stacklang to be used as a simple terminal based program
I quickly realised that the same computation engine could be useful in other
projects. For this reason the core of stacklang is available as a Nim library.
In fact the actual terminal application stacklang is only about 350 lines of Nim
code which imports the library, sets up a couple terminal specific commands, and
runs an input/output loop. The `help` command for example is a stacklang program
extension which reads all the available documentation and prints it to the
terminal. If you're importing stacklang as a library this command won't be
defined and you can implement your own `help` command. Basically stacklanglib
won't ever print anything to the terminal, it will simply take inputs, perform
calculations, and allow the host program to read the stack and other internal
state. I've already created a small terminal based spreadsheet application based
on this library. But it's not quite ready to be published yet. What is described
in this documentation from this point on is about the stacklang terminal
application, but it is almost entirely applicable to the library as well.

## Labels and references
I've already mentioned that labels can point to commands, and that such commands
will be executed as soon as the label is pushed to the stack. I also vaguely
mentioned that you sometimes need to push labels onto the stack without
executing the command they point to. The reason for this is that there are some
commands in stacklang which takes a command label and does something with it.
The easiest such command is probably `explain`:

```
\+ explain
```
This pushes the label `+` onto the stack without executing the plus command, and
then `explain` retrieves the documentation snippet for that command. The above
command would simply print out the documentation, leaving the stack empty:

```
+   n, n   Adds two numbers
```
This shows us the command name `+`, the arguments it takes `n, n`, and the
documentation string `Adds two numbers`. For an explanation of the arguments,
see the documentation section at the end.

Another way labels can be used as references is for naming variable stacks. In
stacklang you don't have your traditional single value variables, instead you
have named stacks. So if you wanted to store the number 42 for example you could
do something like:

```
42 meaningofeverything varpush
```
The `varpush` command takes an element, in this case the number 42, and a label,
in this case "meaningofeverything" and pushes that element onto that stack,
removing it from the current stack. There are many more commands to deal with
these stacks under the "Variable commands" section in the help.

In addition to referencing commands and variables, labels can also be used to
refer to positions on the stack. Many of the commands which takes a number of
elements can also be passed a label instead. This tells stacklang that instead
of a fixed number it should use the position of that label on the stack. So for
example:

```
start "This is a number: " 100 35 10 + - start print
```
Would print the message "This is a number: 55". The `print` command here took
the start label, and then looked back along the stack until it found the next
start label and printed everything in-between. Note that the first `start` label
is still left on the stack after the `print` command completes.

### Numeral references
As we just saw `print` can take either the number of elements to print, or a
label to go back to and print from there. But it can also take negative numbers
or a number zero. In fact all the commands which takes a number or label to go
to can take negative numbers or zero. This is basically just a shorthand for
going back from the end of the stack. So something like this:

```
"Hello" "world" "!" 0 print
```
Wouldn't print zero elements, but it would print all elements from the bottom of
the stack, ie. "Hello world !" (stacklang adds spaces between arguments to
print). And something like this:

```
"Hello" "world" "!" -1 print
```
Would print all but the first element, "world !".

## More advanced usage
With the above information you should be able to use Stacklang as a pretty handy
calculator or even run some nice little calculation scripts with inputs. But to
leverage more power out of Stacklang we need to look at some of the more
advanced usage scenarios. This is where the "programming language" part of
Stacklang comes in.

### Basic looping
The first of these is the `until` command which is a simple looping construct.
It takes two arguments, a stack position and a command. Then it simply runs the
command over and over again until the stack is at the given position. Take for
example:
```
0 \pop until
```
This will run the `pop` command until the stack is at position 0, ie. when the
stack is empty. Of course this position follows the rule of the above chapter on
references:
```
-3 \pop until
```
This will run the `pop` command until the stack is three elements shorter than
what it is currently (after `-3 \pop until` is removed from the stack),
essentially making the stack 3 elements shorter. When passed a label it will
run the command until that label is the topmost element, so it can also be used
to fill the stack:
```
hello 5 \dup until
```
This will add the label `hello` to the stack until it is 5 elements long.

### Taking input
When writing scripts it is often useful to ask the user for input. Stacklang has
two commands for this `input` and `exhaust`. `input` simply reads the next line
of input and pushes each value on the line to the stack. This works in the
interactive shell as well as when piping data into Stacklang. When piping data
`input` will not do anything if the end of the file is reached, it simply
becomes a `nop`. The `exhaust` command will read the entire input until the end
and put everything on the stack. This command is only available when input is a
pipe.

### Creating commands
Of course Stacklang wouldn't be much of a programming language if you weren't
able to create you own commands. You do this by calling the `mkcmd` command, and
commands have a couple extra bells and whistles to them. The `mkcmd` command
takes the same kind of position references that many other commands in Stacklang
does. So an example:
```
0 \\pop \until 0 mkcmd
```
This would push `0 \pop until` onto the stack, and then `0 mkcmd` would create a
command of the entire stack. Since the command doesn't have a name it appears on
the stack something along the lines of `tmp7087`. This is simply a label
referencing a temporary command. Given such a label we can use the `name`
command to name it something more user friendly:
```
[ tmp7087 ]
> clear name
```
The stack is now empty, but if you look at the end of the `help` output you will
now see your command listed at the bottom. And typing `clear` should highlight
it as a command, while trying to push it to the stack will execute the `clear`
command we just defined. Another way to name a command is to use a label
reference for the `mkcmd` command:
```
clear 0 \\pop \until clear mkcmd
```
This will do the same thing, but leave a label `clear` on the stack, pointing to
the newly created command.

Note that you can also document your commands, simply push a string to the
stack, then the label you want to document, and run `doccmd`. The documentation
string will now be available in the `help` message. If you want to delete a
command you can use the `delcmd` command.

To call a temporary command with its label on the stack (or any command with its
label on the stack for that matter) you can use the `call` command. It simply
takes a label and executes that as a command. You can also use `excmd` to expand
the given command, ie. copy the contents of the command onto the stack, this is
useful if you want to edit a command.

Escaping labels onto the command can quickly get annoying though, so Stacklang
provides three commands `noeval`, `noevaluntil`, and `eval` to disable and
enable evaluation of commands. The above clear command can for example be
entered with:

```
noeval 0 \pop until eval 0 mkcmd
```
Or by using the `noevaluntil`, which stops evaluation until a given token is
encountered:
```
\mkcmd noevaluntil 0 \pop until 0 mkcmd
```
In this repository you will also find a "standard library" which includes two
commands, `[` and `]` which uses the `noevaluntil` in a clever way to more
easily create inline commands.

#### More complex commands
Inside a command there are a couple extra commands available. Namely `goback`,
`gofwd`, `lblcnt`, `return`, and `cmdlbl`. These only make sense within a
command environment and allow you to implement some flow control. But they can
be a little bit unfamiliar to use (except `return`, most people are probably
familiar with that one). The two `go` commands simply move execution forwards or
back _within the given command_. So a command like:
```
nothing end \gofwd \exit end nothing mkcmd
```
Would first push `end` to the stack, then run `gofwd` which pops the `end`
label then searches for the last occurence _in the command_, finds the `end`
after the `exit` token and continues the command from there. So this command,
despite containing an `exit` won't actually exit Stacklang. In fact the only
thing this does is leave the final `end` token on the stack. And a command
like:
```
infprint start \pop "Hello" 1 \print start \goback infprint mkcmd
```
Will simply print `Hello` to the terminal forever. The start label is pushed to
the stack, then immediately popped off. Then `"Hello"` is pushed to the stack
along with a `1` which the `print` command picks up and prints the `Hello`
message. Now `start` is pushed to the stack again and `goback` picks it up.
`goback` scans _the command_ backwards until it finds first `start` token and then
continues execution from there. Notice that `goback` looks at _the command_ and
not the current stack when going back. We pushed `start` to the stack before
immediately popping it, so `goback` wouldn't find it if it was searching the
stack. The `goback` and `gofwd` commands jump around _the command_ irrespective of
the stack (although where to go is defined by the stack). Notice that unlike
many of the other commands that take positions `goback` goes to the _first_
occurence of a label in the command and `gofwd` goes to the _last_ occurence in
the command. The `goback` and `gofwd` commands also takes numbers. The `gofwd`
command takes the number of positions to go forward in the command, and if
negative the position away from the end of the command. And the `goback`
command takes the number of positions to go back in the command, and if
negative the position away from the start of the command.

When jumping to labels Stacklang keeps track of how many times each label in the
current command has been jumped to. So in the `infprint` example above the label
`start` will have its count steadily increasing. To get this count you can use
`lblcnt`. So if you wanted to only print ten hellos you could do something like
this:
```
tenprint start \lblcnt "Hello" 1 \print 9 start \\return \< \goback tenprint mkcmd
```
This command will push `start` to the stack, then get its label count, which is
zero since it has never been jumped to. Then `"Hello"` and `1` is pushed to the
stack as before and `print` pops them off and displays the `Hello` message. Now
the number `9` is pushed to the stack along with a `start` label and the
`return` command label. The `<` command (which will be explained more in detail
in the next chapter) takes the number left over by `lblcnt` and the number `9`
and compares them. If the former is smaller than the latter it runs the first
label, in this case `start`, otherwise in runs the second label, in this case
`return`. Now if `return` wasn't called the command continues and `goback` picks
up the `start` label left by the `<` command and the whole command repeats.
Since `start lblcnt` will increase by one every time the `goback` command jumps
to it this will print the "Hello" message ten times before calling `return` and
ending the command. Note that jumping by numerical index and landing on a label
won't increase that labels count.

We briefly discovered `return` above, which simply stops the execution of a
command (to return values simply leave them on the stack). But the last command
`cmdlbl` is still left unexplained. Stacklang doesn't have any real hygiene in
commands, they are all free to do what they want with the stack and any variable
in the entire program. To allow commands a little bit of hygiene the `cmdlbl`
simply pushes a token unique to each instantiation of the command onto the
stack. This is intended to be used to have a variable stack where a command can
store things during execution and then simply be able to run `cmdlbl vardel` to
clear it out after running without having to worry about ruining something else.
You could of course just make sure to push and pop the correct amount of
elements to a stack, put its nice to have the option. Since these commands are
only available in command execution you can't call this in the shell, but you
can abuse it to get random labels with something like:
```
\cmdlbl -1 mkcmd call
```
This simply creates a temporary command which only calls `cmdlbl` and then
immediately runs it, leaving one such random variable on the stack.

### Conditionals
There are six base conditionals in Stacklang, in addition to an `eof`
conditional defined in the interactive shell. They should all be familiar to
programmers, but their stack based nature might be a bit foreign. Each of the
six regular conditionals take two numbers, and two extra elements. They then
compare the numbers and executes either the first, or the second of the extra
elements. As seen above when using the `<` command the elements don't have to
be commands. A label, number, or string will simply get pushed to the stack, but
any command label will get called immediately. For conditionals it is useful to
create temporary commands to supply the two runnable elements. By using the
brackets defined in the standard library in this repository you could do
something like this:
```
10 100 [ "It's smaller!" 1 print] ["It's larger!" 1 print ] <
```
Which in this case will print "It's smaller". Note that the numbers and elements
can of course come from other calculations, they are just on the stack like
anything else. In fact in the sample above the `start lblcnt` was supplying the
first argument to `<` even though it was the very first thing executed in the
command.

The `eof` command supplied by the interactive shell only takes two elements and
simply checks if `stdin` has reached its end. If it has the first element is
evaluated, otherwise the second. So something like this:
```
cat README.md | stacklang 'end [ input 0 print end \nop eof ] until'
```
Will read the entire `README.md` file line by line (executing any commands in
it, so be careful) and print them out. The `eof` command here either pushes the
`end` token to the stack which stops the `until` loop, or it simply is a `nop`
which doesn't do anything and allows the `until` loop to run again (of course if
a line in our file ended with `end` it would quit the loop early, Stacklang
isn't really meant to read text files).

## Documentation
The arguments uses a shorthand comprising of four letters `n` for number, `s`
for string, `l` for label, and `a` for anything. Sometimes you will also see
`l|n` which just means a label or a number. Note that some commands can consume
more elements than those which are listed, `print` for example can be given a
number which specifies how many elements to pop off the stack and print.

```
Math commands:
+         n, n   Adds two numbers
-         n, n   Subtract two numbers
*         n, n   Multiplies two numbers
/         n, n   Divides two numbers
sqrt      n      Takes the square root of a number
^         n, n   Takes one number and raises it to the power of another
sin       n      Takes the sine of a number
sinh      n      Takes the hyperbolic sine of a number
arcsin    n      Takes the arc sine of a number
arcsinh   n      Takes the inverse hyperbolic sine of a number
cos       n      Takes the cosine of a number
cosh      n      Takes the hyperbolic cosine of a number
arccos    n      Takes the arc cosine of a number
arccosh   n      Takes the inverse hyperbolic cosine of a number
tan       n      Takes the tangent of a number
tanh      n      Takes the hyperbolic tangent of a number
arctan    n      Takes the arc tangent of a number
arctanh   n      Takes the inverse hyperbolic tangent of a number
dtr       n      Converts a number from degrees to radians
rtd       n      Converts a number from radians to degrees
mod       n, n   Takes the modulo of one number over another
binom     n, n   Computes the binomial coefficient
fac       n      Computes the factorial of a non-negative number
ln        n      Computes the natural logarithm of a number
log       n, n   Computes the logarithm of the first number to the base of the second

Bitwise commands:
and        n, n   Runs a binary and operation on two numbers
or         n, n   Runs a binary or operation on two numbers
xor        n, n   Runs a binary xor operation on two numbers
not        n      Runs a binary not operation on a number
shl        n, n   Shift a number left by the given amount
shr        n, n   Shift a number right by the given amount
truncbin   n, n   Truncates a binary number

Modifications commands:
round      n         Rounds a number to the closest integer
ceil       n         Rounds a number up
floor      n         Rounds a number down
sgn        n         Returns -1 for negative numbers, 1 for positive, and 0 for 0
splitdec   n         Takes a number and splits it into an integer and floating part
trunc      n         Truncates the floating part off a number
clamp      n, n, n   Clamps a value in between two values

Encoding commands:
hex   n   Converts a number to hex encoding
bin   n   Converts a number to binary encoding
dec   n   Converts a number to decimal encoding
sci   n   Converts a number to scientific notation

Other commands:
nop                    Does nothing
rand                   Adds a random number between 0 and 1 to the stack
noeval                 Stops evaluation, all commands will simply be pushed to the
                       stack
noevaluntil   l        Like noeval, but accepts a label which restarts execution
                       before being evaluated
eval                   When noeval has been called, this will re-enable evaluation
until         l|n, l   Takes a label or a position and runs the given command until
                       the stack is that position
mkcmd         l|n      Takes a label or a position and creates a command of
                       everything from that position to the end of the stack
delcmd        l        Takes a label and deletes the custom command by that name
name          l, l     Takes a label of a command and a label, names (or renames) the
                       command to the label
doccmd        s, l     Takes a string and a label and documents the command by that
                       name
call          l        Calls the given label as a command
excmd         l        Expands the given command onto the stack
goback        l|n      Takes a position in a command and moves back to that position
gofwd         l|n      Takes a position in a command and moves forward to that
                       position
lblcnt        l        Puts the amount of times the given label has been jumped to by
                       gofwd or goback onto the stack
return                 Stops execution of the current command
cmdlbl                 Puts a label onto the stack, the label will be unique to each
                       instance of a command

Stack commands:
pop      a        Pops an element off the stack, discarding it
dup      a        Duplicates the topmost element on the stack
swap     a, a     Swaps the two topmost elements of the stack
rot               Rotates the stack, putting the bottommost element on top
revrot   a        Rotates the stack, putting the topmost element on the bottom
len               Puts the length of the stack on the stack
insert   a, l|n   Takes an element and a position and inserts the element before that
                  position in the stack
delete   l|n      Deletes the element off the stack at a given position
fetch    l|n      Takes the element off the stack at a given position and puts it on
                  top
pos      l|n      Puts the index of the position given on the stack

Variable commands:
varpush   a, l     Takes an element and a label and pushes the element to the stack
                   named by the label
vartake   l|n, l   Takes a position and a label and moves elements from the stack to
                   the variable until it's at the position
varpop    l        Takes a label and pops an element of the stack named by that label
varmrg    l        Takes a label and puts all elements of that variable onto the
                   current stack, deleting the variable
varexp    l        Takes a label and puts all elements of that variable onto the
                   current stack
varswp    l        Takes a label and swaps the current stack for that of the one
                   named by that label
vardel    l        Takes a label and deletes the variable by that name

Conditionals commands:
<    n, n, a, a   If the first number is smaller than the second the third token is
                  evaluated, otherwise the fourth
>    n, n, a, a   If the first number is greater than the second the third token is
                  evaluated, otherwise the fourth
<=   n, n, a, a   If the first number is smaller than or equal to the second the
                  third token is evaluated, otherwise the fourth
>=   n, n, a, a   If the first number is greater than or equal to the second the
                  third token is evaluated, otherwise the fourth
==   n, n, a, a   If the first number is equal to the second the third token is
                  evaluated, otherwise the fourth
!=   n, n, a, a   If the first number is not equal to the second the third token is
                  evaluated, otherwise the fourth

Interactive shell commands:
input            Reads a line from stdin and puts all tokens on the stack. Doesn't do
                 anything on EOF, puts an empty string on an empty line
exhaust          Reads stdin until EOF putting everything on the stack
eof       a, a   Checks if input is at the end of the file, runs the first label if
                 it is, otherwise the second
exit             Exits interactive stacklang, saving custom commands
history          Prints out the entire command history so far
help             Prints out all documentation
explain   l      Prints out the documentation for a single command or category
display   a      Shows the element on top off the stack without poping it
print     l|n    Takes a number of things or a label to go back to, then prints those
                 things in FIFO order with space separators
eprint    l|n    Same as print, but prints to stderr instead of stdout
list             Lists all currently stored variables
```

## Benchmarks
The same way Stacklang isn't really meant to be used as a programming language
it hasn't really been optimised for anything but functioning as an interactive
calculator. None the less you might want to know how it performs. I ran a very
simple test where I generated a file with one million numbers in it, designed to
sum up to something about 3 times the size of what a uint64 can hold. I then
compiled Stacklang with `-d:danger` and LTO enabled and ran the benchmark with:
```
time ./stacklang --script nums.sl 'len length varpush 1 \+ until length varmrg /'
```
It takes about 1.5s to calculate the average. For comparisson a Nim program
using MAPM to compute the same thing takes about 0.3s and a Python program which
uses the built in `int` type uses about 0.2s. The Python version of course just
uses an arbitrary precision integer for the sum, when it runs the final divison
it incorrectly rounds the result. Both Stacklang and the Nim MAPM solution
gives the same result. A Nim version using floats takes about 0.07s, but gives
a result which is 0.565 away from the true result of 27689299975563.106806 which
is still quite good depending on your scenario.

## Size benchmarks
The Stacklang binary compiled for the benchmark above and stripped with
`strip -s` comes out at 555Kb. It only links to libc and libm. Statically linked
it comes up to about 1.7M.

## Stacklang vs. Stacklanglib
As mentioned Stacklang is actually possible to use as a library. The shell
application uses the library and extends it with certain functions. So what
exactly comes from where? Looking at the help message everything which isn't in
the "Interactive shell commands" section comes from the library. So when
importing the library you get everything to do with variables, commands, and of
course all the math operations. The `custom.sl` runner is also part of the
interactive shell, so you will have to read that in yourself if you want to use
it in your application. Besides all this the interactive shell also supports
bash-like history expansion.

### History expansion
Like bash, Stacklang supports history expansion. These only work in the
interactive shell, and work on each "line" of commands. You can use `!!` to
repeat the last line. You can use `!-2` to execute the second to last line. Or
you can use `!0` to run the first line. You can also expand parts of a line so
`!0:1` will take the second token of the first line (they are zero indexed). And
you ran pass a range so `!0:1-2` will take the second and third element. Or just
`!0:1-` to take everything from the second command onwards.
