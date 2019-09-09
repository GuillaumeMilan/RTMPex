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
end
