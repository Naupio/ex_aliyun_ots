defmodule ExAliyunOts.Tunnel.Checkpointer do
  @moduledoc false

  alias ExAliyunOts.Client
  alias ExAliyunOts.Var.Tunnel.{Checkpoint, GetCheckpoint}
  alias ExAliyunOts.Const.Tunnel.Common
  alias ExAliyunOts.Logger

  require Common

  defstruct [:tunnel_id, :client_id, :instance_key, :channel_id, :sequence_number, :token]

  def checkpoint(checkpointer) do
    case do_checkpoint(checkpointer) do
      {:ok, _} ->
        checkpointer.sequence_number + 1

      {:error, error_msg} ->
        Logger.info(fn ->
          "checkpoint occur error: #{inspect(error_msg)}"
        end)

        if String.contains?(error_msg, "OTSSequenceNumberNotMatch") do
          # Occur the conflict of sequence_number, try to update local sequence_number from remote server,
          # and then retry checkpoint.
          var_get_checkpoint = %GetCheckpoint{
            tunnel_id: checkpointer.tunnel_id,
            client_id: checkpointer.client_id,
            channel_id: checkpointer.channel_id
          }

          get_checkpoint_result =
            Client.get_checkpoint(checkpointer.instance_key, var_get_checkpoint)

          case get_checkpoint_result do
            {:ok, response} ->
              checkpointer
              |> Map.put(:sequence_number, response.sequence_number + 1)
              |> checkpoint()

            error ->
              Logger.error(fn ->
                "checkpoint occur OTSSequenceNumberNotMatch error, retry get checkpoint but get error: #{
                  inspect(error)
                }"
              end)

              raise ExAliyunOts.Error,
                    "GetCheckpoint occur error: #{inspect(error)} while retry checkpoint."
          end
        else
          raise ExAliyunOts.Error, "Checkpoint occur error_msg: #{inspect(error_msg)}."
        end
    end
  end

  defp do_checkpoint(checkpointer) do
    token = if checkpointer.token == nil, do: Common.finish_tag(), else: checkpointer.token

    var_checkpoint = %Checkpoint{
      tunnel_id: checkpointer.tunnel_id,
      client_id: checkpointer.client_id,
      channel_id: checkpointer.channel_id,
      checkpoint: token,
      sequence_number: checkpointer.sequence_number
    }

    Client.checkpoint(checkpointer.instance_key, var_checkpoint)
  end
end