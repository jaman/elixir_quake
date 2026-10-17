defmodule ElixirQuake.Gpu.Slots do
  @moduledoc """
  Instance ids for things that come and go between ticks. A key keeps its id for as long
  as it is shown every tick; the id of a key no longer shown is removed from the scene
  and given out again from the next tick on.

      {ids, removals, slots} = ElixirQuake.Gpu.Slots.assign(slots, [{:entity, 12}, :weapon])
      {id, fresh?} = Map.fetch!(ids, :weapon)

  Ids start at `first` (`new/1`), so the ids below it stay free for the caller's own use.
  """

  @type key :: term()
  @type t :: %__MODULE__{
          ids: %{key() => pos_integer()},
          free: [pos_integer()],
          next: pos_integer()
        }

  @enforce_keys [:ids, :free, :next]
  defstruct [:ids, :free, :next]

  @doc "No keys yet; ids are given out from `first`."
  @spec new(pos_integer()) :: t()
  def new(first), do: %__MODULE__{ids: %{}, free: [], next: first}

  @doc """
  The ids of this tick's `keys`, each with whether it is new this tick; the
  `{:remove_instance, id}` changes for keys shown last tick and not now; and the slots
  after.
  """
  @spec assign(t(), [key()]) ::
          {%{key() => {pos_integer(), boolean()}}, [CauldronGPU.Stream.change()], t()}
  def assign(%__MODULE__{} = slots, keys) do
    shown = MapSet.new(keys)
    {kept, gone} = Map.split_with(slots.ids, fn {key, _id} -> MapSet.member?(shown, key) end)
    old = Map.new(kept, fn {key, id} -> {key, {id, false}} end)

    {ids, free, next} =
      keys
      |> Enum.uniq()
      |> Enum.reduce({old, slots.free, slots.next}, &give/2)

    removals = for {_key, id} <- gone, do: {:remove_instance, id}

    {ids, removals,
     %__MODULE__{
       ids: Map.new(ids, fn {key, {id, _fresh?}} -> {key, id} end),
       free: free ++ Map.values(gone),
       next: next
     }}
  end

  @doc "Every id given out."
  @spec ids(t()) :: [pos_integer()]
  def ids(%__MODULE__{ids: ids}), do: Map.values(ids)

  defp give(key, {ids, free, next}) when is_map_key(ids, key), do: {ids, free, next}
  defp give(key, {ids, [id | free], next}), do: {Map.put(ids, key, {id, true}), free, next}
  defp give(key, {ids, [], next}), do: {Map.put(ids, key, {next, true}), [], next + 1}
end
