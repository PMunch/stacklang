# Welcome to Stacklang
Contrary to it's name stacklang is not meant to be a programming language as
such. Rather it tries to be an easy to use, but very powerful calculator. To
achieve this the design is very simple, but with the potential to create more
complexity through defining custom commands. But let's start with the basics!

## Data types
The inputs to stacklang is a series of elements separated by spaces, called a
command. Commands can be composed of three different things:

- Numbers
- Operations
- Labels

Numbers are easy, it's anything that can be parsed into a double precision
floating point number (note that this might be changed in the future). This
includes things like `42`, `3.14`, `10e5`, and even `inf` and `nan`. You can
also separate thousands groups by on underscore like so `10_000`, in fact you
can put underscores between any two numbers. The rule for float parsing is
described in the Nim manual:
https://nim-lang.github.io/Nim/manual.html#lexical-analysis-numerical-constants
You can also use the three constants `pi`, `tau`, and `e`.

Operations are also familiar, `+`, `*`, `sqrt`, `sin`, etc. Since stacklang is
a stack-based RPN calculator they might not work exactly like you expect, but
we'll come back to that in the next chapter. All operations are called
immediately as they are encountered. To see all the available operations try
the `help` operation.

Labels are simply any word, or rather anything without spaces in it. For
example `hello`, `my2cents`, `100bottles` etc. In order to allow a label to
reference an operation you can prefix it with a backslash: `\+`, `\sqrt`,
`\sin` etc. This will add the operation without the prefix instead of running
it.

## Stack-based calculation
In the section on Operations above it was mentioned that stacklang is a stack-
based RPN calculator. This means that instead of the more common infix notation
`2 + 4` it uses postfix notation `2 4 +`. While it might be unfamiliar at first
it's actually a really powerful way of performing calculations. At the heart of
any RPN calculator is the stack. Numbers are pushed onto the stack, and
operations pop elements of the stack and push the result back. Consider the
above example `2 4 +`, first the `2` is pushed onto the stack, then the `4`,
then when we encounter the `+` operation it pops the two elements off the,
stack adds them together, and pushes the result back onto the stack. Note that
`+` only takes two operands. So the "command" (in stacklang parlance) `1 2 3 +`
would leave us with a stack of `1 5` since `2` and `3` have been added together
and the result pushed back. The power of this system is easier to see if we
look at a slightly more complicated example
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

## Labels and referencing
But as previously mentioned stacklang doesn't only have numbers and operations,
it also has labels. So what are they used for? Maybe the most familiar use-case
would be to store a value as a named variable. Running `2 4 + myvar store` will
do the calculation, then push the label `myvar` and then run the operation
`store`. If we now run the command `list` we'll see that `myvar` has been
assigned to the value `6`. This is because `store` takes an element, and a
label, and assigns that element to the label. The word element is used here as
we can also store labels in variables. To delete the variable and put the
element back on our stack we can use `load`, which simply takes a label, so
`myvar load` will now put `6` back on our stack.

Since labels can also be the name of an operation there is a command `call`
that executes an operation. So `5 10 \+` will put the three elements `5`, `10`,
and the label `+` onto our stack, and then running `call` will execute the `+`
operation and sum our two numbers. This is useful for a command such as `until`
which takes an operation as a label and executes it until a condition is met.

This `until` command is only one of a handful of operations that repeats an
action given a condition. And these conditions are common amongst all of them,
so it's best to describe it together. The commands that take this kind of
condition are `print`, `until`, `insert`, `delete`, `mkcmd`, `gofwd`, and
`goback`. If they are given a positive number, or `0`, it is considered an
index on the stack. So `hi 0 insert` will insert the label `hi` at the very
beginning of the stack, similarily `0 print` will print the contents of the
stack, and remove all the elements (not so useful in the CLI, but might be
interesting for scripting). The aforementioned `until` operator treats this as
a target stack length, and will execute the operation it's given until the
stack is at that length. So `0 \pop until` will clear the entire stack. The two
goto commands does something similar but on the current command, `goback` will
treat it as an index, and `gofwd` will treat it is a reverse index. So
`0 goback` will start the command all over again, and `0 gofwd` will execute
the last statement in the command.

If they are given a negative number it's seen as relative to the current stack
length, so `-5 print` will print the last five elements, and `-3 delete` will
remove the 3rd element from the end (after `-3` and `delete` are removed). The
`until` operation once again treats it as a length and `-3 \pop until` will
execute `pop` until the stack is 3 elements shorter than it is currently.
Similarily `goback` will go back the number of elements and `gofwd` will go
forward the number of elements in the command. Note that `-1 gofwd` will
execute the operation right after the `gofwd` operation.

The last thing that can be passed in is a label, this will make the command
look back through the stack until it finds that label and then execute there
(with the noteable exception of `goback` that goes to the first occurence in
the command, and `gofwd` that goes to the last). So `100 200 text These are
words text print` will print the labels "These are words" and remove everything
but `100 200` from the stack. And againt `until` treats this as its target for
the top of the stack so `hello \pop until` will remove elements until `hello`
is the top element on the stack.

## Making custom operations
This is all well and good, but the true power of stacklang comes from creating
your own custom operations. A custom operation is simply a command that is
bound to a label so that it will be executed just like the built in commands.
Say for example that we're tired of typing `0 \pop until` when we want to clear
the entire stack. To make this easier we can use `mkcmd` to create a custom
operation that will call that command each time it's run. As mentioned in the
previous chapter `mkcmd` takes the same kind of references that many things
in stacklang does. So to declare this command we can do
`0 \\pop \until -3 mkcmd`, note that we need to double escape `pop` and escape
`until` to avoid them being actually executed directly, or when our command is
executed. When `mkcmd` is given an index, relative or otherwise, it will create
a random label for us and push that to the stack. So the above command will
result in a stack with one element that looks something like this: `tmp7087`.
If we execute `lscmd` we can see all the defined custom operations and the so
called temporary operations. These temporary commands are deleted as soon as
they are called or their label is removed from the stack as long as they are
not referenced from another command or when they are called by `until`. The
`until` command will stores the command internally before deleting it so it can
be run multiple times). Stacklang will automatically save all your custom
operations in a file when you execute `exit`, but temporary operations are lost
if not already deleted.

To create a custom operation instead of a temporary operation we can
either execute `name` with a label, and the temporary label we were given. So
with our `tmp7087` label on the stack we can call `mycmd swap name` which will
push `mycmd` to the stack, swap the two elements around so our stack is
`mycmd tmp7087` and then rename `tmp7087` to `mycmd`. The more ergonomic way
of doing this would be to push `mycmd` onto the stack _before_ we create our
command: `mycmd 0 \\pop \until -3 mkcmd name`. Here `mycmd` will be pushed to
the stack, followed by `0` and the labels `\pop` and `until`, then `-3 mkcmd`
will remove those elements, create a command, and push a temporary label to the
stack leaving us with `mycmd tmp7087` before our `name` command is executed.
But to simplify things even further we can use label referencing. When `mkcmd`
is called with a label instead of an index it will loop backwards for that
label, and take everything following it and create a command with the same name
as the label. This will not leave the label on the stack. So the command
`sayhello hello world -2 \print sayhello mkcmd` will create a new command
`sayhello` that will print "hello world". When naming commands keep in mind
that anything that might look like a label could also be a command, so if you
want to print text like this make sure that neither `hello` or `world` is a
command. A common trick is to pre- or postfix all your custom commands with a
certain symbol like `'`, `.`, or `-`, just pick something that's easy to write.

If you ever need to change a custom operation you can use the `excmd` operation
to put the operation back onto the stack, edit it, and then bind it back to the
same name. Just make sure to escape the name of your operation when adding it
to the stack for naming so you don't end up calling it.

## Branching logic, gotos, loops, and commands within commands
When creating more complex operations it's often useful to control how our data
is handled. For example we might want to handle two ranges of data differently
in a function, or we might want to provide error messages or other output to
the user based on our calculation. For this we need branching logic. The
branching logic in stacklang is fairly simple, you have the operators `<`, `>`,
`=`, `!=`, `<=`, and `>=`. All of these operators will compare the two previous
elements, and if they are true will execute the next operation and skip the
one after that. If they result is false it will skip the next operation and
execute the one after that. So for example `100 200 < smaller larger` would
leave the label `smaller` as the only thing on the stack since `100` is smaller
than `200`. If you want to do more complex things than what can be achieved in
a single operation you can make a temporary operation, or leave a label on the
stack you can `call`, `gofwd`, or `goback`. This might be a bit more tricky
than you'd initially think since commands are run left-to-right, so creating a
temporary operation in-line will not work:
`100 200 < smaller -1 \print -3 mkcmd larger -1 \print -3 mkcmd`. This complains
that the stack ran out of options, this is because when `<` is encountered it
will be executed and `smaller` will be put on the stack, then `print` and `-3`
will be put on the stack followed by trying to execute `mkcmd` which now
expects three elements. To circumvent this you can either create and name your
branches before-hand, or make a temporary command out of the comparisson:
`100 200 \< smaller -1 \print -3 mkcmd larger -1 \print -3 mkcmd -3 mkcmd` if
we look at our stack now it reads `100 200 tmpXXXX`. And looking in `lscmd` we
can see that our two branches have been crated as temporary operations with the
comparisson also created as an operation that calls either of the branches. By
now executing `call` the comparisson will be run.

Another way of solving this problem, which is arguably cleaner, is to use the
`gofwd` operation and indices or labels. The above could be written as:
`100 200 < -1 -6 gofwd smaller -1 print end gofwd larger -1 print end pop` or
with labels:
`100 200 < if else gofwd if smaller -1 print end gofwd else larger -1 print end
gofwd end`. If this example looks really complicated it's partially because it
doesn't do much, this makes more sense if you do more stuff within your
branches. The above is of course much more easily solved by
`100 200 < smaller larger -1 print` but this wouldn't work if we wanted to
print more than a single element.

Another thing that is commonly wanted is to do something more than once. While
you could certainly copy-paste things over and over it's better to put them in
a loop. This also allows the number of iterations to be dynamic, based on the
value of an execution for example. Apart from using `until` the easiest way to
create a loop is to use `lblcnt`. It accepts a label and gives a count of how
many times this label has been the target of `goback` or `gofwd`. So in order
to print "hello world" ten times you can do:
`start hello world -2 print start lblcnt 9 < goback pop`. First we add a label
`start` which is also pushed to our stack. Then the command
`hello world -2 print` will print the two labels `hello` and `world` while
removing them from our stack. After that the `start` label is pushed again so
we have two instances of it. Our next operation `lblcnt` will pop one of the
labels, and add the count for how many times it has been gone to, which for now
is 0. And since 0 is smaller than 9 `goback` is executed, it pops the `start`
label that's on the stack and goes to the first instance of it in the command,
which is at the beginning of our loop. This happens over and over until the
`lblcnt` operation returns 9, which then pops the last start label off the
stack again. This is analagous to a do-while loop as all the statements are run
once before the loop starts.

## Hygiene in custom operators
Since every operation in a stacklang shares the stack, variables, and custom
operation space it's important to not "litter" when your custom operation is
executed. In the above example you can see that we do `< goback pop` were the
`pop` cleans up the label we would otherwise go to. Sometimes however it might
be tricky to get your stack set up right, but try to stay away from bad
practices like calling `0 \pop until` at the end of operations for "cleanup".
If you want to make sure the stack is clean before you return you can do
something like this:
`cleanhello \len \rand \store 42 34 hello -1 \print \lstrand \load \\pop \until
cleanhello mkcmd` which creates a new custom operator `cleanhello` that pushes
some elements to the stack, prints hello, and then cleans up after itself.
It's sometimes necessary to name something, but not really caring what it is
named as long as it doesn't collide with anything. For this  we have the `rand`
operation which creates a random label that is guaranteed to not crash with any
custom operation name or variable name. These are also stored on an internal
stack, and `lstrand` can be used to pop the last generated random label off
this stack. Just be sure to pop and push the same amount of these labels you
use in your custom operator, otherwise other things requiring the same system
might misbehave. Another option is to store these internal values in a name
prefixed with the operator name, but this means we can't call the operator in a
loop without overwriting the variable.
