defmodule ReceiverMessage do
  defstruct [:payload, :delivery_tag, :correlation_id, :reply_to]
end
