defmodule RTMP.MessageManager do
  require Logger
  def receive_message(:handshake1, client) do
    receive_until(client,
      fn <<_::bytes-size(1537)>> -> true
        _ -> false
      end)
  end
  def receive_message(:handshake2, client) do
    receive_until(client,
      fn <<_::bytes-size(1536)>> -> true
        _ -> false
      end)
  end
  def receive_message(:connected, client) do
    receive_until(client, fn _ -> true end)
  end
  
  def receive_until(client, finished, previous_chunk \\ <<>>) do
    Logger.debug("RECEIVE UNTIL #{byte_size(previous_chunk)}")
    {:ok, chunk} = :gen_tcp.recv(client, 0)
    if finished.(previous_chunk<>chunk), do: previous_chunk<>chunk, else: receive_until(client, finished, previous_chunk<>chunk)
  end

  def receive_a_chunk(client) do
    {:ok, chunk} = :gen_tcp.recv(client, 0)
    chunk
  end


  @doc """
  Decode a low level chunk received from a RTMP connection (As described in the specification section: **5.3 Chunking**)
  If the chunk is not respecting the expected format the function crash

  Example:

  If you have received a previous chunk in the chunk stream, you can do:
  ```
  RTMP.MessageManager.read_chunk(previous_chunk, chunk)
  ```
  Else you can simply do:
  ```
  RTMP.MessageManager.read_chunk(%RTMP.MessageManager.Chunk.Header{}, chunk)
  ```
  """
  def read_chunk(previous_chunk, chunk) do
    {_header_info, _chunk_data} = RTMP.MessageManager.Chunk.Header.read({previous_chunk, chunk})
  end
end

defmodule RTMP.MessageManager.TestHelper do
  @moduledoc """
  Helper to test example provided by the Specifications

  Simple chunk reading:
  ```
  RTMP.MessageManager.Chunk.Header.read({%RTMP.MessageManager.Chunk.Header{}, RTMP.MessageManager.TestHelper.example_chunk(:fmt_0)})
  ```

  Multiple chunk reading accumulation:
  ```
  Enum.reduce(
    RTMP.MessageManager.TestHelper.example_chunks(:video),
    [{%RTMP.MessageManager.Chunk.Header{}, ""}],
    fn c, [{last_header, _}|_] = acc ->
      [RTMP.MessageManager.Chunk.Header.read({last_header, c})|acc]
    end
  ) |> Enum.reverse() |> Enum.slice(1..-1)
  ```
  """

  def example_chunk(:fmt_0) do
    <<
      0b00111111, # fmt 0 -- cs_id 63
      <<1000::size(24)>>, # timestamp
      <<32::size(24)>>, # message length
      <<8::size(8)>>, # message type
      <<1234::size(32)>>, # message stream id
    >>
    <> "My message"
  end

  def example_chunks(:video) do #We assum chunk size is 128 in this example (Section 5.3.2.2)
    [
      <<
        0b00000100, # ftm 0 -- cs_id 4
        <<1000::size(24)>>, # timestamp 1000
        <<307::size(24)>>, # message length 307 
        <<9::size(8)>>, # message type 9 == video
        <<12346::size(32)>>, # message stream id
      >><><<0::size(1456)>>, # 128 bytes large message
      <<
        0b11000100, # ftm 3 -- cs_id 4
      >><><<0::size(1456)>>,
      <<
        0b11000100, # ftm 3 -- cs_id 4
      >><><<0::size(408)>>,
    ]
  end
end

defmodule RTMP.MessageManager.Chunk.Header do
  require Logger
  
  defstruct fmt: 0, chunk_stream_id: 0, timestamp: 0, message_length: 0, message_type_id: 0, message_stream_id: 0, most_recent_fmt: -1, extended_timestamp: false

  @maximum_timestamp 16777215

  # We create the header from the preceding chunk header as some fields can come from it
  def read({preceding_chunk_header, chunk}) do
    {preceding_chunk_header, chunk}
    |> read_basic_header()
    |> read_message_header()
    |> eventually_read_extended_timestamp()
  end

  def format(_data) do
    {:error, :not_implemented}
  end

  def read_basic_header({preceding_chunk_header, chunk}) do
    case read_basic_header_1({preceding_chunk_header, chunk}) do
      {:complete, partially_read_header, rem_chunk} -> {partially_read_header, rem_chunk}
      {:type_2, partially_read_header, rem_chunk} -> read_basic_header_2(partially_read_header, rem_chunk)
      {:type_3, partially_read_header, rem_chunk} -> read_basic_header_3(partially_read_header, rem_chunk)
    end
  end

  def read_message_header({
    %{fmt: 0} = partially_read_header,
    <<timestamp::size(24)>> <>
    <<message_length::size(24)>> <>
    <<message_type_id::size(8)>> <>
    <<message_stream_id::size(32)>> <>
    rem_chunk
  }) do
    {
      %{partially_read_header|
        timestamp: timestamp,
        message_length: message_length,
        message_type_id: message_type_id,
        message_stream_id: message_stream_id,
        most_recent_fmt: 0,
        extended_timestamp: timestamp == @maximum_timestamp
      },
      rem_chunk
    }
  end
  def read_message_header({
    %{fmt: 1} = partially_read_header,
    <<timestamp_delta::size(24)>> <>
    <<message_length::size(24)>> <>
    <<message_type_id::size(8)>> <>
    rem_chunk
  }) do
    {
      %{partially_read_header|
        timestamp: ensure_timestamp(partially_read_header.timestamp, timestamp_delta),
        message_length: message_length,
        message_type_id: message_type_id,
        most_recent_fmt: 1,
        extended_timestamp: timestamp_delta == @maximum_timestamp
      },
      rem_chunk
    }
  end
  def read_message_header({
    %{fmt: 2} = partially_read_header,
    <<timestamp_delta::size(24)>> <>
    rem_chunk
  }) do
    {
      %{partially_read_header|
        timestamp: ensure_timestamp(partially_read_header.timestamp, timestamp_delta),
        most_recent_fmt: 2,
        extended_timestamp: timestamp_delta == @maximum_timestamp},
      rem_chunk
    }
  end
  def read_message_header({
    %{fmt: 3, most_recent_fmt: most_recent_fmt} = partially_read_header,
    rem_chunk
  }) when most_recent_fmt in [0, 1, 2] do
    {partially_read_header, rem_chunk}
  end

  def eventually_read_extended_timestamp({%{most_recent_fmt: most_recent_fmt, extended_timestamp: true} = partially_read_header, <<timestamp::size(32)>><>rem_chunk}) when most_recent_fmt in [0, 1, 2] do
    if most_recent_fmt == 1 do
      {%{partially_read_header|timestamp: timestamp}, rem_chunk}
    else
      {%{partially_read_header|timestamp: partially_read_header.timestamp + timestamp}, rem_chunk}
    end
  end
  def eventually_read_extended_timestamp({%{most_recent_fmt: most_recent_fmt} = partially_read_header, rem_chunk}) when most_recent_fmt in [0, 1, 2] do
    {partially_read_header, rem_chunk}
  end

  def read_basic_header_1({preceding_chunk_header, <<first_byte::size(8)>><>rem_chunk}) do
    case extract_header_1_cs_id(first_byte) do
      0 -> {:type_2, %{preceding_chunk_header| fmt: extract_fmt(first_byte)}, rem_chunk}
      1 -> {:type_3, %{preceding_chunk_header| fmt: extract_fmt(first_byte)}, rem_chunk}
      chunk_stream_id -> {:complete,  %{preceding_chunk_header| fmt: extract_fmt(first_byte), chunk_stream_id: chunk_stream_id}, rem_chunk}
    end
  end

  def read_basic_header_2(partially_read_header, <<second_byte::size(8)>><>rem_chunk) do
    {%{partially_read_header|chunk_stream_id: second_byte+64}, rem_chunk}
  end

  def read_basic_header_3(partially_read_header, <<second_bytes::size(16)>><>rem_chunk) do
    {%{partially_read_header|chunk_stream_id: second_bytes+64}, rem_chunk}
  end

  def extract_header_1_cs_id(basic_header_byte) do
    Bitwise.&&&(0b00111111, basic_header_byte)
  end

  def extract_fmt(basic_header_byte) do
    Bitwise.>>>(basic_header_byte, 6)
  end

  def ensure_timestamp(previous_timestamp, @maximum_timestamp) do
    previous_timestamp
  end

  def ensure_timestamp(previous_timestamp, received_timestamp) do
    previous_timestamp + received_timestamp
  end
end
