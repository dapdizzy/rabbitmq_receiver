defmodule RabbitMQReceiver do
  use GenServer

  defstruct [:connection, :channel, :queue_name, :callback_module, :callback_function, :no_ack]

  #APi
  @doc """
  Starts linked RabbitMQReceive rprocess and returns it's pid, or raises otherwise.
  """
  def start_link(rabbit_options \\ [], queue_name, callback_module, callback_function, no_ack \\ true, gen_server_options \\ [])
  when rabbit_options |> is_list
    and callback_module |> is_atom
    and callback_function |> is_atom do
    effective_rabbit_options =
      case rabbit_options do
        [] -> Application.get_env(:rabbitmq_receiver, :rabbit_options, [])
        _ -> rabbit_options
      end
    case GenServer.start_link RabbitMQReceiver, [effective_rabbit_options, queue_name, callback_module, callback_function, no_ack], gen_server_options do
      {:ok, pid} = good -> good
      {:error, reason} -> raise "Failed to initialize RabbitMQReceiver with reason #{inspect reason}"
      :ignore -> raise "Your request has been ignored"
      _ -> raise "Something unexpected had happent"
    end
  end

  def ack_delivery(server, delivery_tag) do
    server |> GenServer.call({:ack_delivery, delivery_tag})
  end

  # Callbacls
  def init([rabbit_options, queue_name, callback_module, callback_function, no_ack]) do
    {:ok, connection} = AMQP.Connection.open rabbit_options
    {:ok, channel} = AMQP.Channel.open connection
    AMQP.Queue.declare channel, queue_name
    AMQP.Basic.consume channel, queue_name, nil, no_ack: no_ack
    IO.puts "Receiving messages from queue #{queue_name}"
    {:ok, %RabbitMQReceiver{connection: connection, channel: channel, queue_name: queue_name, callback_module: callback_module, callback_function: callback_function, no_ack: no_ack}}
  end

  def handle_info({:basic_deliver, payload, meta}, %RabbitMQReceiver{callback_module: callback_module, callback_function: callback_function, no_ack: no_ack} = state) do
    apply(callback_module, callback_function, [(unless no_ack, do: {payload, meta.delivery_tag}, else: payload)])
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
end
