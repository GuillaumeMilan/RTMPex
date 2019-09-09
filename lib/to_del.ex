defmodule ToDel do
  use GenServer
  require Logger
  def start_link do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end
  def init(_) do
    {:ok, :ok}
  end

  def wait_for_connection do
    {:ok, port} = :gen_tcp.listen(1234, [])
    {:ok, socket} = :gen_tcp.accept(port)
    Logger.debug("#{inspect receive_until(socket, [])}")
    :ok = :gen_tcp.close(socket)
    :ok = :gen_tcp.close(port)
  end
  defp receive_until(socket, prev_chunks) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, chunk} -> 
        Logger.debug("#{inspect chunk}")
        receive_until(socket, [chunk, prev_chunks])
      {:error, :closed} -> prev_chunks
    end
  end
  def receive_message(socket) do
    receive_until(socket, [])
  end
end
