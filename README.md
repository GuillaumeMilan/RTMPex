# RTMPex

**RTMPex** is a library that provides a easy to use RTMP client for **Elixir**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `rtmp` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:rtmp, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/rtmp](https://hexdocs.pm/rtmp).

## Developpement status

| Feature | Status |
| --- | --- |
| Server connection handshake | Done & Tested |
| Chunk header reading | Done & To be tested in real situation |
| Chunk formatting | Todo |
| Control message parsing | Todo |
| Control message formatting | Todo |
