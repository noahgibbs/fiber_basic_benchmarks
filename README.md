# Simple Load Tests on Fibers vs Threads

Based closely on Samuel Williams' RubyKaigi talk "Fibers are the Right Solution" (slides: https://www.codeotaku.com/journal/2018-11/fibers-are-the-right-solution/index), I've built out some very simple HTTP servers that return a tiny static response to (they assume) a simple HTTP request.

This is about as minimal as a Ruby HTTP server can get. That means that the overhead should be nearly all overhead from the chosen method of concurrency - in this case threads vs fibers.

Samuel's code using async and async-io uses nio4r under the hood, and thus a libev-based reactor. This *should* result in substantially lower overhead than a pure-Ruby implementation based on IO.select. It's more comparable to a reactor-based solution like Puma (threads, reactor, optional process-based concurrency in clustered mode) than a trivial server like these.

It's not easy to benchmark the full implementation in earlier Ruby versions. The Falcon application server is a production-quality reactor-and-fiber implementation, but neither Falcon nor its dependencies currently support older Ruby versions.

The intent is to follow thread vs fiber overhead back to Ruby version 2.0.
