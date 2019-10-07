# Simple Load Tests on Fibers vs Threads

After some work, I wound up using interprocess pipes for testing threads versus processes versus fibers. They turn out to have low overhead and low variance, especially when compared to TCP sockets...

Important parts of the fiber code are based on Samuel Williams' RubyKaigi talk "Fibers are the Right Solution" (slides: https://www.codeotaku.com/journal/2018-11/fibers-are-the-right-solution/index). Samuel also contributed some code more directly (https://github.com/socketry/async/blob/master/benchmark/rubies/benchmark.rb)

You can see my initial writeup of this code, how it was written and its results here:

* http://engineering.appfolio.com/appfolio-engineering/2019/9/13/benchmarking-fibers-threads-and-processes
* http://engineering.appfolio.com/appfolio-engineering/2019/9/4/benchmark-results-threads-processes-and-fibers
