defmodule RTMP.Server.Connection do
  use GenServer
  require Logger


  def start_link({socket, server}, opts), do: GenServer.start_link(__MODULE__, {socket, server}, opts)

  def init({socket, server}) do
    id = :crypto.strong_rand_bytes(1528)
    {:ok, %{server: server, id: id, socket: socket}, {:continue, :start_connection}}
  end

  def handle_continue(:start_connection, state) do
    case RTMP.Server.Connection.HandShakeFSM.start_connection(state) do
      {:ok, new_state} ->
        {:noreply, enrich_with_default_params(new_state)}
      error ->
        Logger.error("[#{__MODULE__}][#{inspect self()}] Error while handshaking closing connection now. Reason #{inspect error}")
        {:stop, :normal}
    end
  end

  def enrich_with_default_params(state) do
    Map.merge(
      %{
        chunk_size: 128,

      }
  end
end

defmodule RTMP.Server.Connection.HandShakeFSM do
  require Logger
  @moduledoc """
  Connection FSM:
  - :handshaking_phase1 -----------> Receive C0 -------------> :handshaking_phase1
  - :handshaking_phase1 -----------> Receive C1 -------------> :handshaking_phase2
  - :handshaking_phase2 -----------> Receive C2 -------------> :stateected
  """

  def start_connection(state) do
    initial_state = :waiting_for_connection
    process_handshake(initial_state, state)
  end

  def process_handshake(:waiting_for_connection, %{socket: socket, server: server} = state) do
    case :gen_tcp.accept(socket) do
      {:ok, client} ->
        Logger.debug("[#{__MODULE__}][#{inspect self()}] New connection opened")
        GenServer.cast(server, {:connection_accpeted, self()})
        start_timestamp = :os.system_time(:millisecond)
        process_handshake(
          :handshaking_phase1,
          state
          |> Map.put(:client, client)
          |> Map.put(:start_timestamp, start_timestamp)
        )
      reason ->
        Logger.error("[#{__MODULE__}] Error on waiting connection to open #{inspect reason}")
        GenServer.cast(server, {:connection_refused, self()})
        {:error, :unable_to_accept}
    end
  end
  def process_handshake(:handshaking_phase1, %{client: client} = state) do
    case RTMP.MessageManager.receive_message(:handshake1, client) do
      <<0x03, time::bytes-size(4), 0, 0, 0, 0, rand::bytes-size(1528)>> -> # we wait until receiving C0 and C1 (lazy enough)
        #Logger.debug("[#{__MODULE__}][#{inspect self()}] Receive C0 and C1")
        server_time = server_time(state.start_timestamp)
        send_s1(client, server_time, state.id)
        send_s2(client, time, server_time, rand)
        process_handshake(:handshaking_phase2,state)
      message ->
        inspect_message = "<<#{to_bytes(message, []) |> Enum.map(fn <<x>> -> x end)|> Enum.join(", ")}>>"
        Logger.warn("[#{__MODULE__}][#{inspect self()}] Bad message received #{inspect_message} \nWith a length of #{length(to_bytes(message, []))}")
        {:error, :unexpected_phase1_message}
    end
  end
  def process_handshake(:handshaking_phase2, %{client: client} = state) do
    case RTMP.MessageManager.receive_message(:handshake2, client) do
      <<_server_timestamp::bytes-size(4), _time::bytes-size(4), _rand::bytes-size(1528)>> ->
        {:ok, state}
      message ->
        inspect_message = "<<#{to_bytes(message, []) |> Enum.map(fn <<x>> -> x end)|> Enum.join(", ")}>>"
        Logger.warn("[#{__MODULE__}][#{inspect self()}] Bad message received #{inspect_message} \nWith a length of #{length(to_bytes(message, []))}")
        {:error, :unexpected_phase2_message}
    end
  end

  # Not used I don't know why client is not asking for it.
  def send_s0(client) do
    Logger.debug("[Connection] Sending S0 #{inspect <<0x03>>}")
    :gen_tcp.send(client, <<0x03>>)
  end

  def send_s1(client, server_time, id) do
    message = <<0x03>> <> server_time <> id
    :gen_tcp.send(client, message)
  end

  def send_s2(client, receive_time, sent_time, client_id) do
    message = receive_time <> sent_time <> client_id
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
