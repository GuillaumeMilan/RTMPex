defmodule RTMP.Server do
  use GenServer
  @moduledoc """
    Server that monitor the gen_tcp listen port
  """
  require Logger

  #TODO Monitor connection if the quit by their self
  
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts[:port], opts)

  def init(port) do
    Process.send(self(), :listen, [])
    {:ok, port} = :gen_tcp.listen(port, [:binary, {:packet, 0}, {:active, false}])
    {:ok, %{port: port, connections: []}}
  end

  def terminate(_reason, %{port: port, connections: connections}) do
    IO.puts("CLOSING #{inspect port}")
    :gen_tcp.close(port)
    IO.puts("CLOSED #{inspect port}")
    Enum.each(connections, fn c -> 
      Logger.debug("EXITING #{inspect c}")
      Process.exit(c, :kill)
    end)
  end

  def handle_info(:listen, %{port: port, connections: connections}) do
    {:ok, socket} = :gen_tcp.accept(port)
    {:ok, new_connection} = RTMP.Connection.start_link([socket: socket])
    Process.send(self(), :listen, [])
    {:noreply, %{port: port, connections: [new_connection|connections]}}
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end
end
