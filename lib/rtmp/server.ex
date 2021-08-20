defmodule RTMP.Server do
  use GenServer
  require Logger

  @moduledoc """
  Start a multiple connection RTMP server

  pool_size define the number of waiting connection in parallel, there is no connection count limit
  ```
  {:ok, pid} = RTMP.Server.start_link([port: 1234, pool_size: 10], [])
  ```

  TODO The servers crash on connection dying on crash. Crash handling is to be implemented
  """

  def start_link(rtmp_opts, genserver_opts), do: GenServer.start_link(__MODULE__, rtmp_opts, genserver_opts)

  def child_spec(rtmp_opts) do
    ensure_rtmp_opts(rtmp_opts)
    port = Keyword.fetch!(rtmp_opts, :port)
    %{
      id: {__MODULE__, {'localhost', port}},
      restart: :permanent,
      start: {__MODULE__,:start_link, [rtmp_opts, []]},
      type: :worker,
    }
  end

  def ensure_rtmp_opts(rtmp_opts) do
    _ = Keyword.fetch!(rtmp_opts, :port)
    _ = Keyword.fetch!(rtmp_opts, :pool_size)
  end

  def init(rtmp_opts) do
    port = Keyword.fetch!(rtmp_opts, :port)
    pool_size = Keyword.fetch!(rtmp_opts, :pool_size)
    {:ok, socket} = :gen_tcp.listen(port, [:binary, {:packet, 0}, {:active, false}])
    Process.flag(:trap_exit, true)
    pids = start_pool(pool_size, socket)
    {:ok, %{socket: socket, waiting_clients: pids, clients: []}}
  end

  def handle_cast({:connection_accpeted, from}, %{socket: socket, waiting_clients: waiting_clients, clients: clients} = state) do
    true = from in waiting_clients
    {:ok, pid} = RTMP.Server.Connection.start_link({socket, self()}, [])
    new_waiting_clients = [pid|Enum.reject(waiting_clients, &(&1 == from))]
    {:noreply, %{state| waiting_clients: new_waiting_clients, clients: [from|clients]}}
  end

  def handle_cast({:connection_refused, from}, %{socket: socket, waiting_clients: waiting_clients, clients: clients} = state) do
    true = from in waiting_clients
    {:ok, pid} = RTMP.Server.Connection.start_link({socket, self()}, [])
    new_waiting_clients = [pid|Enum.reject(waiting_clients, &(&1 == from))]
    {:noreply, %{state| waiting_clients: new_waiting_clients, clients: clients}}
  end

  def handle_cast({:unregister_client, pid}, %{clients: clients} = state) do
    {:noreply, %{state|clients: Enum.reject(clients, &(&1 == pid))}}
  end

  def handle_call(:get_clients, _from, %{clients: clients} = state) do
    {:reply, clients, state}
  end

  def terminate(reason, %{socket: socket}) do
    Logger.debug("[Server]: Closing socket due to #{inspect reason}")
    :gen_tcp.close(socket)
  end

  def start_pool(pool_size, socket) do
    Enum.map(1..pool_size, fn _ ->
      {:ok, pid} = RTMP.Server.Connection.start_link({socket, self()}, [])
      pid
    end)
  end
end
