defmodule RTMP.Connection do
  use GenServer
  @moduledoc """
  Server that monitor a connection through gen_tcp
  """
  require Logger
  
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts[:socket], opts)

  def init(socket) do
    Process.send(self(), :process, [])
    {:ok, %{socket: socket}}
  end
  
  def terminate(_reason, %{socket: socket}) do
    :gen_tcp.close(socket)
  end

  def handle_info(:process, %{socket: socket}) do
    message = receive_until(socket, [])
    Logger.debug("RECEIVED FULL MESSAGE #{inspect message}", ansi_color: :green)
    {:stop, :normal, %{socket: socket}}
  end

  def receive_until(socket, previous_chunks) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, chunk} -> 
        Logger.debug("RECIEVED: #{inspect chunk}")
        receive_until(socket, [chunk , previous_chunks])
      {:error, :closed} -> previous_chunks 
    end
  end
end
