defmodule RabbitMQReceiverTest do
  use ExUnit.Case
  doctest RabbitMQReceiver

  test "greets the world" do
    assert RabbitMQReceiver.hello() == :world
  end
end
