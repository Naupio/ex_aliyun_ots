defmodule ExAliyunOts.Tunnel.Registry do
  @moduledoc false
  use GenServer

  alias ExAliyunOts.Tunnel.{EntryWorker, EntryChannel}
  import EntryWorker
  import EntryChannel

  @table_worker :registry_worker

  @table_channel :registry_channel

  def start_link(), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def init(_) do
    t_worker =
      :ets.new(@table_worker, [
        :set,
        :named_table,
        :public,
        keypos: 2,
        read_concurrency: true,
        write_concurrency: true
      ])

    t_channel =
      :ets.new(@table_channel, [
        :set,
        :named_table,
        :public,
        keypos: 2,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, {t_worker, t_channel}}
  end

  @spec new_worker(EntryWorker.entry_worker()) :: boolean
  def new_worker(entry_worker() = registry) do
    :ets.insert_new(@table_worker, registry)
  end

  @spec new_channel(EntryChannel.entry_channel()) :: boolean
  def new_channel(entry_channel() = registry) do
    :ets.insert_new(@table_channel, registry)
  end

  @spec channels(tunnel_id :: String.t()) :: list()
  def channels(tunnel_id) when is_binary(tunnel_id) do
    case :ets.match(
           @table_channel,
           entry_channel(
             channel_id: :"$1",
             tunnel_id: tunnel_id,
             client_id: :"$2",
             pid: :"$3",
             status: :"$4",
             version: :"$5"
           )
         ) do
      [] ->
        []

      list when is_list(list) ->
        Enum.map(list, fn record ->
          List.insert_at(record, 1, tunnel_id)
        end)
    end
  end

  @spec channel(channel_id :: String.t()) :: nil | tuple()
  def channel(channel_id) when is_binary(channel_id) do
    case :ets.lookup(@table_channel, channel_id) do
      [] ->
        nil

      [items] when is_tuple(items) ->
        Tuple.delete_at(items, 0) |> Tuple.to_list()
    end
  end

  @spec remove_worker(tunnel_id :: String.t()) :: true
  def remove_worker(tunnel_id) when is_binary(tunnel_id) do
    :ets.delete(@table_worker, tunnel_id)
  end

  @spec remove_channel(channel_id :: String.t()) :: true
  def remove_channel(channel_id) when is_binary(channel_id) do
    :ets.delete(@table_channel, channel_id)
  end

  @spec remove_channel(channel_pid :: pid()) :: boolean()
  def remove_channel(channel_pid) when is_pid(channel_pid) do
    case :ets.match(
           @table_channel,
           entry_channel(
             channel_id: :"$1",
             tunnel_id: :_,
             client_id: :_,
             pid: channel_pid,
             status: :_,
             version: :_
           )
         ) do
      [] -> false
      [[channel_id]] -> remove_channel(channel_id)
    end
  end

  @spec inc_channel_version(channel_id :: String.t(), inc_offset :: integer()) :: term()
  def inc_channel_version(channel_id, inc_offset \\ 1) do
    :ets.update_counter(
      @table_channel,
      channel_id,
      {EntryChannel.index(:version) + 1, inc_offset}
    )
  end

  @spec workers() :: list()
  def workers() do
    :ets.tab2list(@table_worker)
    |> Enum.map(fn entry_worker(tunnel_id: tunnel_id, client_id: client_id, pid: pid, meta: meta) ->
      {tunnel_id, client_id, pid, meta}
    end)
  end

  @spec update_worker(tunnel_id :: String.t(), updates :: [{atom(), term()}]) :: boolean()
  def update_worker(tunnel_id, updates) do
    fields = Enum.map(updates, fn {k, v} -> {EntryWorker.index(k) + 1, v} end)
    :ets.update_element(@table_worker, tunnel_id, fields)
  end

  @spec update_channel(channel_id :: String.t(), updates :: [{atom(), term()}]) :: boolean()
  def update_channel(channel_id, updates) do
    fields = Enum.map(updates, fn {k, v} -> {EntryChannel.index(k) + 1, v} end)
    :ets.update_element(@table_channel, channel_id, fields)
  end

  @spec worker(tunnel_id :: String.t()) :: nil | term()
  def worker(tunnel_id) when is_binary(tunnel_id) do
    case :ets.lookup(@table_worker, tunnel_id) do
      [] -> nil
      [items] when is_tuple(items) -> Tuple.delete_at(items, 0) |> Tuple.to_list()
    end
  end

  @spec worker(worker_pid :: pid()) :: nil | term()
  def worker(worker_pid) when is_pid(worker_pid) do
    case :ets.match(
           @table_worker,
           entry_worker(tunnel_id: :"$1", client_id: :"$2", pid: worker_pid, meta: :"$3")
         ) do
      [] ->
        nil

      [list] when is_list(list) ->
        List.insert_at(list, 2, worker_pid)
    end
  end
end