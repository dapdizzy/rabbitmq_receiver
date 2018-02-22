defmodule RabbitMQReceiver do
  use GenServer

  defstruct [:connection, :channel, :queue_name, :callback_module, :callback_function, :no_ack, :exchange, :binding_keys, :rpc_mode]

  #APi
  @doc """
  Starts linked RabbitMQReceive rprocess and returns standard {:ok, pid}, or raises otherwise.
  Note that a callback_moddule.callback_function now accepts a %ReceiverMessage{} struct instead of tuples.
  option_switches - is intended for passing options determining various integration types and the way the queue and exchanges and stuff is configured.
  Now, supported options are:
  :exchange - which indicated that the queue has a configured exchange (not a default one).
  :exchange_type - denotes the type of the Exchange. Supported values include: :direct, :fanout, :topic, :match (and :headers).
  :binding_keys - a list of values denoting topics bound to the queue.
  Option switches should be provided either as a keyword lists (where value is required according to the meaning) or as options (just atoms in the list).
  """
  def start_link(rabbit_connection_options \\ [], queue_name, callback_module, callback_function, no_ack \\ true, gen_server_options \\ [], option_switches \\ [])
  when rabbit_connection_options |> is_list
    and callback_module |> is_atom
    and callback_function |> is_atom do
    effective_rabbit_options =
      case rabbit_connection_options do
        [] -> Application.get_env(:rabbitmq_receiver, :rabbit_options, [])
        _ -> rabbit_connection_options
      end
    case GenServer.start_link RabbitMQReceiver, [effective_rabbit_options, queue_name, callback_module, callback_function, no_ack, option_switches], gen_server_options do
      {:ok, _pid} = good -> good
      {:error, reason} -> raise "Failed to initialize RabbitMQReceiver with reason #{inspect reason}"
      :ignore -> raise "Your request has been ignored"
      _ -> raise "Something unexpected had happent"
    end
  end

  def ack_delivery(server, delivery_tag) do
    server |> GenServer.call({:ack_delivery, delivery_tag})
  end

  # Callbacks
  def init([rabbit_options, queue_name, callback_module, callback_function, no_ack, option_switches]) do
    {:ok, connection} = AMQP.Connection.open rabbit_options
    {:ok, channel} = AMQP.Channel.open connection
    exchange =
      with exchange_name when exchange_name |> is_binary() <- option_switches[:exchange] do
        AMQP.Exchange.declare(channel, exchange_name, option_switches[:exchange_type] || :direct) # Declare an exchange if we have a topic option passed in.
        exchange_name
      end
    effective_queue_name =
      cond do
        queue_name |> is_binary() && queue_name != "" ->
          AMQP.Queue.declare channel, queue_name
          queue_name
        (with exchange_name when exchange_name |> is_binary() and exchange_name != "" <- option_switches[:exchange],
          :topic <- option_switches[:exchange_type],
          [_h|_t] <- option_switches[:binding_keys]
        do
          true
        end) == true ->
          {:ok, %{queue: generated_queue_name}} = AMQP.Queue.declare(channel, "", exclusive: true)
          generated_queue_name
        true ->
          raise "Nither a queue name was specified, nor an exchange was properly configured"
      end
    unless effective_queue_name |> is_binary() do
      raise "Unable to create a queue"
    end
    binding_key_list =
      with [_h|_t] = binding_keys <- option_switches[:binding_keys] do
        for binding_key <- binding_keys do
          AMQP.Queue.bind(channel, effective_queue_name, exchange, routing_key: binding_key)
        end
        binding_keys
      end
    AMQP.Basic.consume channel, effective_queue_name, nil, no_ack: no_ack
    IO.puts "Receiving messages from queue #{effective_queue_name}"
    {:ok,
      %RabbitMQReceiver
      {
        connection: connection,
        channel: channel,
        queue_name: effective_queue_name,
        callback_module: callback_module,
        callback_function: callback_function,
        no_ack: no_ack,
        exchange: exchange,
        binding_keys: binding_key_list,
        rpc_mode: (if option_switches[:rpc_mode], do: true, else: false)
      }
    }
  end

  def handle_info({:basic_deliver, payload, meta},
    %RabbitMQReceiver
    {
      callback_module: callback_module,
      callback_function: callback_function,
      no_ack: no_ack,
      rpc_mode: rpc_mode
    } = state) do
    apply(
      callback_module,
      callback_function,
      [
        %ReceiverMessage
        {
          payload: payload,
          delivery_tag: (unless no_ack, do: meta.delivery_tag),
          correlation_id: meta[:correlation_id],
          reply_to: (if rpc_mode, do: meta.reply_to)
        }
      ])
      # [(unless no_ack, do: {payload, meta.delivery_tag}, else: payload)])
    {:noreply, state}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  def handle_call({:ack_delivery, delivery_tag}, _from, %RabbitMQReceiver{channel: channel, no_ack: no_ack} = state) do
    result =
      unless no_ack do
        AMQP.Basic.ack(channel, delivery_tag)
      else
        :no_ack
      end
    {:reply, result, state}
  end

  @moduledoc """
  Documentation for RabbitMQReceiver.
  """

  @doc """
  Hello world.

  ## Examples

      iex> RabbitMQReceiver.hello
      :world

  """
  def hello do
    :world
  end

  def puts_inspected(value) do
    value |> inspect |> IO.puts
  end

end
