defmodule RTMP.Server2 do
  use GenServer
  require Logger

  def start_link(port, opts), do: GenServer.start_link(__MODULE__, port, opts)

  def init(port) do
    {:ok, socket} = :gen_tcp.listen(port, [:binary, {:packet, 0}, {:active, false}])
    GenServer.cast(self(), :create_connection)
    {:ok, %{socket: socket, clients: []}}
  end

  def terminate(reason, %{socket: socket}) do
    Logger.debug("[Server]: Closing scoket du to #{inspect reason}")
    :gen_tcp.close(socket)
  end
  
  def handle_cast(:create_connection, %{socket: socket} = state) do
    {:ok, pid} = RTMP.Connection2.start_link({socket, self()}, [])
    :ok = :gen_tcp.controlling_process(socket, pid)
    {:noreply, Map.update!(state, :clients, fn clients -> [pid|clients] end)}
  end

  def handle_cast({:register_client, client}, state) do
    {:noreply, Map.update!(state, :clients, fn clients -> [client|clients] end)}
  end
  def handle_cast({:unregister_client, client}, state) do
    Logger.debug("[Server] Unregistering client #{inspect client}")
    {:noreply, Map.update!(state, :clients, fn clients -> Enum.filter(clients, &(&1 != client)) end)}
  end
end

defmodule RTMP.Connection2 do
  use GenServer
  require Logger
    
  @moduledoc """
    
  Connection FSM:
  - :handshaking_phase1 -----------> Receive C0 -------------> :handshaking_phase1
  - :handshaking_phase1 -----------> Receive C1 -------------> :handshaking_phase2
  - :handshaking_phase2 -----------> Receive C2 -------------> :connected
  """
  def start_link({socket, server}, opts), do: GenServer.start_link(__MODULE__, {socket, server}, opts)

  def init({socket, server}) do
    {:ok, client} = :gen_tcp.accept(socket)
    GenServer.cast(self(), :waiting_message)
    GenServer.cast(server, :create_connection)
    id = :crypto.strong_rand_bytes(1528)
    start_timestamp = :os.system_time(:millisecond)
    {:ok, %{server: server, client: client, fsm: %{state: :handshaking_phase1}, id: id, start_timestamp: start_timestamp}}
  end

  def terminate(reason, %{client: client, server: server}) do
    Logger.debug("[Connection] Closing connection due to #{inspect reason}")
    :gen_tcp.close(client)
    GenServer.cast(server, {:unregister_client, self()})
  end

  def handle_cast(:waiting_message, %{client: client, fsm: %{state: :handshaking_phase1}} = state) do
    case RTMP.MessageManager.receive_message(:handshake1, client) do
      <<0x03, time::bytes-size(4), 0, 0, 0, 0, rand::bytes-size(1528)>> -> # we wait until receiving C0 and C1 (lazy enough)
        Logger.debug("[Connection] Receive C0 and C1")
        server_time = server_time(state.start_timestamp)
        send_s1(client, server_time, state.id)
        send_s2(client, time, server_time, rand)
        GenServer.cast(self(), :waiting_message)
        {:noreply, (state |> Map.update!(:fsm, fn _ -> %{state: :handshaking_phase2} end))}
      message ->
        inspect_message = "<<#{to_bytes(message, []) |> Enum.map(fn <<x>> -> x end)|> Enum.join(", ")}>>"
        Logger.debug("[Connection] Bad message received #{inspect_message} \nWith a length of #{length(to_bytes(message, []))}")
        {:stop, :error}
    end
  end
  def handle_cast(:waiting_message, %{client: client, fsm: %{state: :handshaking_phase2}} = state) do
    case RTMP.MessageManager.receive_message(:handshake2, client) do
      <<_server_timestamp::bytes-size(4), _time::bytes-size(4), _rand::bytes-size(1528)>> -> 
        Logger.debug("[Connection] Receive C2")
        GenServer.cast(self(), :waiting_message)
        {:noreply, (state |> Map.update!(:fsm, fn _ -> %{state: :connected} end))}
      message -> 
        inspect_message = "<<#{to_bytes(message, []) |> Enum.map(fn <<x>> -> x end)|> Enum.join(", ")}>>"
        Logger.debug("[Connection] Bad message received #{inspect_message} \nWith a length of #{length(to_bytes(message, []))}")
        {:stop, :error}
    end
  end
  def handle_cast(:terminate, _state) do
    {:stop, :terminated}
  end
  def handle_cast(message, state) do
    Logger.debug("[Connection] Receive message #{inspect message} \nWith state #{inspect state}")
    {:noreply, state}
  end

  def send_s0(client) do
    Logger.debug("[Connection] Sending S0 #{inspect <<0x03>>}")
    :gen_tcp.send(client, <<0x03>>)
  end

  def send_s1(client, server_time, id) do
    message = <<0x03>> <> server_time <> id
    Logger.debug("[Connection] Sending S1 #{inspect message}")
    :gen_tcp.send(client, message)
  end

  def send_s2(client, receive_time, sent_time, client_id) do
    message = receive_time <> sent_time <> client_id
    Logger.debug("[Connection] Sending S2 #{inspect message}")
    :gen_tcp.send(client, message)
  end

  def server_time(start) do
    #TODO Modulo for long stream ^^
    <<(:os.system_time(:millisecond) - start)::32>>
  end

  def to_bytes("", list) do
    list |> Enum.reverse
  end
  def to_bytes(string, list) do
    <<b::bytes-size(1)>> <> rest = string
    to_bytes(rest, [b|list])
 end
end
