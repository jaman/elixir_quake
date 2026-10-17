defmodule ElixirQuake.Menu do
  @moduledoc """
  Quake's menus, as the player moves through them: the main menu, single player,
  options, customize controls, help and quit, each answering the keys Quake's do.

      menu = ElixirQuake.Menu.open(settings)
      %{menu: menu, settings: settings, sounds: sounds} = ElixirQuake.Menu.event(menu, {:key, :down}, settings)

  `event/3` returns what `Cauldron2D.Client.Game`'s `menu_event/3` returns, the menu
  holding the settings it shows (`:settings`). The options
  it changes live in the settings: key bindings, the sound volume, where the game is
  drawn (`:drawing`: auto, software, the graphics card in the terminal, or a window), and
  under
  `:options` the screen size (30 to 120), gamma (0.5 to 1.0, lower brighter), mouse
  speed (1 to 11), always run and invert mouse. "Use mouse" adds or removes the mouse
  bindings of the `mouse` preset. New game is sent to the world as the request
  `:new_game`; quitting leaves it, its prompt answered yes by y or a controller's `A`
  (`{:key, :enter, [:pad]}`) and no by n or escape, other keys ignored. Multiplayer,
  loading and saving answer that they are not part of this game.
  """

  alias Cauldron2D.Input
  alias ElixirQuake.Menu.Quit

  defstruct page: :main,
            cursor: %{main: 0, single: 0, options: 0, keys: 0},
            grab?: false,
            help: 0,
            notice: nil,
            back: :main,
            quit: 0,
            settings: %{}

  @type t :: %__MODULE__{}

  @commands [
    {"attack", :fire},
    {"change weapon", :next_weapon},
    {"previous weapon", :prev_weapon},
    {"jump / swim up", :jump},
    {"walk forward", :forward},
    {"backpedal", :back},
    {"turn left", :turn_left},
    {"turn right", :turn_right},
    {"run", :run},
    {"step left", :strafe_left},
    {"step right", :strafe_right},
    {"look up", :look_up},
    {"look down", :look_down},
    {"center view", :center_view}
  ]

  @options [
    :customize,
    :reset,
    :screen_size,
    :gamma,
    :mouse_speed,
    :volume,
    :drawing,
    :always_run,
    :invert_mouse,
    :use_mouse
  ]
  @counts %{main: 5, single: 3}
  @drawings [:auto, :software, :pane, :window]
  @help_pages 6

  @doc "The player options and their defaults."
  @spec defaults() :: map()
  def defaults,
    do: %{screen_size: 100, gamma: 1.0, mouse_speed: 3.0, always_run: false, invert_mouse: false}

  @doc "The controls the customize page lists, as `{name, action}`."
  @spec commands() :: [{String.t(), atom()}]
  def commands, do: @commands

  @doc "The options page's items, in order."
  @spec option_items() :: [atom()]
  def option_items, do: @options

  @doc "The menu as Escape opens it: the main menu, with a quit message chosen."
  @spec open(map()) :: t()
  def open(settings), do: %__MODULE__{quit: :rand.uniform(Quit.count()) - 1, settings: settings}

  @doc "Whether the mouse is bound to anything in `settings`."
  @spec mouse?(map()) :: boolean()
  def mouse?(settings),
    do:
      Enum.any?(settings.bindings, fn {_action, keys} ->
        Enum.any?(keys, &match?({:mouse, _}, &1))
      end)

  @doc "Take one event; see the module documentation for what comes back."
  @spec event(t(), term(), map()) :: map()
  def event(%__MODULE__{grab?: true} = menu, event, settings), do: grab(menu, event, settings)

  def event(%__MODULE__{page: :quit} = menu, {:key, :enter, [:pad]}, settings),
    do: page(:quit, :y, menu, settings)

  def event(%__MODULE__{} = menu, event, settings) do
    case key_of(event) do
      nil -> stay(menu, settings)
      key -> page(menu.page, key, menu, settings)
    end
  end

  defp key_of({:key, key}), do: key
  defp key_of({:key, key, _mods}), do: key
  defp key_of(_event), do: nil

  defp page(:main, :escape, _menu, settings), do: %{menu: nil, settings: settings}
  defp page(:single, :escape, menu, settings), do: stay(%{menu | page: :main}, settings)
  defp page(:options, :escape, menu, settings), do: stay(%{menu | page: :main}, settings)
  defp page(:keys, :escape, menu, settings), do: stay(%{menu | page: :options}, settings)
  defp page(:help, :escape, menu, settings), do: stay(%{menu | page: :main}, settings)

  defp page(:quit, :y, _menu, settings), do: %{menu: nil, settings: settings, leave: true}

  defp page(:quit, key, menu, settings) when key in [:escape, :n],
    do: stay(%{menu | page: menu.back}, settings)

  defp page(:quit, _key, menu, settings), do: stay(menu, settings)

  defp page(:notice, _key, menu, settings),
    do: stay(%{menu | page: menu.back, notice: nil}, settings)

  defp page(:help, key, menu, settings) when key in [:left, :up],
    do: stay(%{menu | help: Integer.mod(menu.help - 1, @help_pages)}, settings, "misc/menu1.wav")

  defp page(:help, key, menu, settings) when key in [:right, :down],
    do: stay(%{menu | help: Integer.mod(menu.help + 1, @help_pages)}, settings, "misc/menu1.wav")

  defp page(name, :up, menu, settings) when name in [:main, :single, :options, :keys],
    do: move(menu, name, -1, settings)

  defp page(name, :down, menu, settings) when name in [:main, :single, :options, :keys],
    do: move(menu, name, 1, settings)

  defp page(:main, :enter, menu, settings) do
    case menu.cursor.main do
      0 -> stay(%{menu | page: :single}, settings, "misc/menu2.wav")
      1 -> notice(menu, "Multiplayer is not part of", "this game.", settings)
      2 -> stay(%{menu | page: :options}, settings, "misc/menu2.wav")
      3 -> stay(%{menu | page: :help, help: 0}, settings, "misc/menu2.wav")
      4 -> stay(%{menu | page: :quit, back: :main}, settings, "misc/menu2.wav")
    end
  end

  defp page(:single, :enter, menu, settings) do
    case menu.cursor.single do
      0 -> %{menu: nil, settings: settings, request: :new_game, sounds: [sound("misc/menu2.wav")]}
      _ -> notice(menu, "Saving and loading are not", "part of this game.", settings)
    end
  end

  defp page(:options, key, menu, settings) when key in [:left, :right, :enter],
    do: option(Enum.at(@options, menu.cursor.options), key, menu, settings)

  defp page(:keys, :enter, menu, settings) do
    {_name, action} = Enum.at(@commands, menu.cursor.keys)

    settings =
      if length(Map.get(settings.bindings, action, [])) > 1,
        do: unbind(settings, action),
        else: settings

    stay(%{menu | grab?: true}, settings, "misc/menu2.wav")
  end

  defp page(:keys, key, menu, settings) when key in [:backspace, :delete] do
    {_name, action} = Enum.at(@commands, menu.cursor.keys)
    stay(menu, unbind(settings, action), "misc/menu2.wav")
  end

  defp page(_page, _key, menu, settings), do: stay(menu, settings)

  defp move(menu, name, step, settings) do
    count = count(name)
    cursor = Map.update!(menu.cursor, name, &Integer.mod(&1 + step, count))
    stay(%{menu | cursor: cursor}, settings, "misc/menu1.wav")
  end

  defp count(:options), do: length(@options)
  defp count(:keys), do: length(@commands)
  defp count(name), do: Map.fetch!(@counts, name)

  defp option(:customize, :enter, menu, settings),
    do: stay(%{menu | page: :keys}, settings, "misc/menu2.wav")

  defp option(:reset, :enter, menu, settings), do: stay(menu, reset(settings), "misc/menu2.wav")

  defp option(item, _key, menu, settings) when item in [:customize, :reset],
    do: stay(menu, settings)

  defp option(item, key, menu, settings) do
    direction = if key == :left, do: -1, else: 1
    stay(menu, adjust(item, direction, settings), "misc/menu3.wav")
  end

  defp adjust(:screen_size, d, s),
    do: put_option(s, :screen_size, clamp(s.options.screen_size + d * 10, 30, 120))

  defp adjust(:gamma, d, s),
    do: put_option(s, :gamma, clamp(Float.round(s.options.gamma - d * 0.05, 2), 0.5, 1.0))

  defp adjust(:mouse_speed, d, s),
    do: put_option(s, :mouse_speed, clamp(s.options.mouse_speed + d * 0.5, 1.0, 11.0))

  defp adjust(:volume, d, s), do: %{s | sfx: clamp(Float.round(s.sfx + d * 0.1, 2), 0.0, 1.0)}

  defp adjust(:drawing, d, s) do
    index = Enum.find_index(@drawings, &(&1 == Map.get(s, :drawing, :auto))) || 0
    Map.put(s, :drawing, Enum.at(@drawings, Integer.mod(index + d, length(@drawings))))
  end

  defp adjust(:always_run, _d, s), do: put_option(s, :always_run, not s.options.always_run)

  defp adjust(:invert_mouse, _d, s) do
    s = put_option(s, :invert_mouse, not s.options.invert_mouse)
    %{s | bindings: look_bindings(s.bindings, s.options.invert_mouse, mouse?(s))}
  end

  defp adjust(:use_mouse, _d, s), do: use_mouse(s, not mouse?(s))

  defp put_option(settings, key, value),
    do: %{settings | options: Map.put(settings.options, key, value)}

  defp clamp(value, low, high), do: value |> max(low) |> min(high)

  defp reset(settings) do
    keymaps = ElixirQuake.Client.keymaps()

    %{
      settings
      | preset: :keyboard,
        bindings: Keyword.fetch!(keymaps, :keyboard),
        options: defaults(),
        sfx: 0.85
    }
  end

  defp use_mouse(settings, true) do
    mouse = Keyword.fetch!(ElixirQuake.Client.keymaps(), :mouse)

    bindings =
      Map.new(mouse, fn {action, keys} ->
        added = Enum.filter(keys, &match?({:mouse, _}, &1))
        {action, Enum.uniq(Map.get(settings.bindings, action, []) ++ added)}
      end)

    settings = %{settings | preset: :mouse, bindings: Map.merge(settings.bindings, bindings)}
    %{settings | bindings: look_bindings(settings.bindings, settings.options.invert_mouse, true)}
  end

  defp use_mouse(settings, false) do
    bindings =
      Map.new(settings.bindings, fn {action, keys} ->
        {action, Enum.reject(keys, &match?({:mouse, _}, &1))}
      end)

    %{settings | preset: :keyboard, bindings: bindings}
  end

  defp look_bindings(bindings, _inverted?, false), do: bindings

  defp look_bindings(bindings, inverted?, true) do
    {up, down} =
      if inverted?,
        do: {{:mouse, :move_down}, {:mouse, :move_up}},
        else: {{:mouse, :move_up}, {:mouse, :move_down}}

    pointer = [{:mouse, :move_up}, {:mouse, :move_down}]

    bindings
    |> Map.update(:look_up, [up], &((&1 -- pointer) ++ [up]))
    |> Map.update(:look_down, [down], &((&1 -- pointer) ++ [down]))
  end

  defp grab(menu, event, settings) do
    case {key_of(event), Input.spec_of(event)} do
      {:escape, _} ->
        stay(%{menu | grab?: false}, settings, "misc/menu1.wav")

      {_, nil} ->
        stay(menu, settings)

      {_, spec} ->
        stay(%{menu | grab?: false}, bind(settings, menu.cursor.keys, spec), "misc/menu2.wav")
    end
  end

  defp bind(settings, cursor, spec) do
    {_name, action} = Enum.at(@commands, cursor)
    freed = Map.new(settings.bindings, fn {other, keys} -> {other, List.delete(keys, spec)} end)
    %{settings | bindings: Map.update(freed, action, [spec], &(&1 ++ [spec]))}
  end

  defp unbind(settings, action),
    do: %{settings | bindings: Map.put(settings.bindings, action, [])}

  defp notice(menu, first, second, settings),
    do:
      stay(
        %{menu | page: :notice, notice: [first, second], back: menu.page},
        settings,
        "misc/menu2.wav"
      )

  defp stay(menu, settings), do: %{menu: %{menu | settings: settings}, settings: settings}

  defp stay(menu, settings, name),
    do: %{menu: %{menu | settings: settings}, settings: settings, sounds: [sound(name)]}

  defp sound(name), do: {:sound, name, 1.0}
end
