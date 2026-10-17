defmodule ElixirQuake.Client do
  @moduledoc """
  Quake as a `Cauldron2D.Client.Game`: the keys, the picture the terminal shows and the
  sounds.

      mix quake --dir /games/quake

  The whole pane is the game's own picture (`ElixirQuake.Render`), drawn at the pane's
  size in whatever the terminal shows best, or by a graphics card (`ElixirQuake.Gpu`)
  when the picture options ask for `gpu` or `window`.

  ## Keys

    * `W`/`S` or `↑`/`↓` — forward and back; `A`/`D` — strafe; `←`/`→` — turn
    * `T`/`G` or `PgUp`/`PgDn` — look up and down; `C` or `End` — look straight ahead
    * `F` — fire; `Space` — jump (and swim up); `R` — run while held
    * `Q`/`E` — previous and next weapon; `1`–`8` — a weapon

  `Esc` opens Quake's own menu (`ElixirQuake.Menu`): single player, options, help and
  quit. Options holds customize controls, screen size, brightness, mouse speed, sound
  volume, always run, invert mouse and use mouse; the game is paused while it is open.
  Use mouse adds the mouse: moving it turns and looks, the left button fires, the right
  button runs, and the wheel changes weapon.

  ## Controller

    * left stick — move and strafe; right stick — turn and look, each as far as pushed;
      the d-pad walks and turns
    * right trigger — fire; left trigger — run; `A` — jump; `X` — look straight ahead
    * the bumpers — previous and next weapon; `Start` — the menu, where the d-pad moves,
      `A` chooses and `B` goes back
  """

  @behaviour Cauldron2D.Client.Game

  alias ElixirQuake.{Assets, Game, Gpu, Menu, Render, View}

  @atlas :elixir_quake

  @impl true
  def title, do: %{name: "QUAKE", tagline: "in Elixir, in your terminal"}

  @impl true
  def atlas do
    unless Cauldron2D.Atlas.installed?(@atlas) do
      @atlas |> Cauldron2D.Atlas.new(tile: 16, void: {0, 0, 0}) |> Cauldron2D.Atlas.install()
    end

    @atlas
  end

  @impl true
  def actions do
    [
      :forward,
      :back,
      :turn_left,
      :turn_right,
      :strafe_left,
      :strafe_right,
      :look_up,
      :look_down,
      :center_view,
      :run,
      :fire,
      :jump,
      :next_weapon,
      :prev_weapon
    ] ++ Enum.map(1..8, &:"weapon_#{&1}")
  end

  @impl true
  def keymaps do
    keys =
      Map.merge(
        %{
          forward: [:w, :up],
          back: [:s, :down],
          turn_left: [:left],
          turn_right: [:right],
          strafe_left: [:a],
          strafe_right: [:d],
          look_up: [:t, :page_up],
          look_down: [:g, :page_down],
          center_view: [:c, :end],
          run: [:r],
          fire: [:f],
          jump: [:" "],
          prev_weapon: [:q],
          next_weapon: [:e]
        },
        Map.new(1..8, &{:"weapon_#{&1}", [:"#{&1}"]})
      )

    mouse = %{
      turn_left: [{:mouse, :move_left}],
      turn_right: [{:mouse, :move_right}],
      look_up: [{:mouse, :move_up}],
      look_down: [{:mouse, :move_down}],
      fire: [{:mouse, :left}],
      run: [{:mouse, :right}],
      prev_weapon: [{:mouse, :wheel_up}],
      next_weapon: [{:mouse, :wheel_down}]
    }

    [keyboard: keys, mouse: Map.merge(keys, mouse, fn _action, key, button -> key ++ button end)]
  end

  @impl true
  def padmap(_props) do
    %{
      forward: [:dpad_up, {:axis, :left_y, :neg}],
      back: [:dpad_down, {:axis, :left_y, :pos}],
      strafe_left: [{:axis, :left_x, :neg}],
      strafe_right: [{:axis, :left_x, :pos}],
      turn_left: [:dpad_left, {:axis, :right_x, :neg}],
      turn_right: [:dpad_right, {:axis, :right_x, :pos}],
      look_up: [{:axis, :right_y, :neg}],
      look_down: [{:axis, :right_y, :pos}],
      center_view: [:x],
      fire: [{:axis, :right_trigger, :pos}],
      run: [{:axis, :left_trigger, :pos}, :left_stick],
      jump: [:a],
      prev_weapon: [:left_bumper],
      next_weapon: [:right_bumper]
    }
  end

  @impl true
  def client_pad,
    do: %{menu: :start, settings: nil, projection: nil, turn_left: nil, turn_right: nil}

  @impl true
  def toggles, do: []

  @impl true
  def holds do
    for action <- [
          :forward,
          :back,
          :turn_left,
          :turn_right,
          :strafe_left,
          :strafe_right,
          :look_up,
          :look_down,
          :run,
          :fire,
          :jump
        ],
        do: {action, 160}
  end

  @impl true
  def client_keys do
    %{
      menu: :escape,
      back: nil,
      settings: nil,
      settings_menu: nil,
      title: nil,
      talk: nil,
      watch: nil,
      team: nil,
      chat: nil,
      guide: nil,
      projection: nil,
      turn_left: nil,
      turn_right: nil,
      tilt_up: nil,
      tilt_down: nil,
      zoom_in: nil,
      zoom_out: nil,
      zoom_reset: nil
    }
  end

  @impl true
  def options, do: Menu.defaults()

  @impl true
  def open_menu(settings), do: Menu.open(settings)

  @impl true
  def menu_event(menu, event, settings), do: Menu.event(menu, event, settings)

  @impl true
  def input_options(options),
    do: [gesture_ms: round(40 + Map.get(options, :mouse_speed, 3.0) * 20)]

  @impl true
  def start, do: {:play, :quake}

  @impl true
  def look,
    do: %{
      projection: :picture,
      projections: [:picture],
      native: {320, 200},
      picture: [{:native, 1}, :swap]
    }

  @impl true
  def chat?, do: false

  @impl true
  def lobby?, do: false

  @impl true
  def worlds(props) do
    game_opts = [map: Map.get(props, :map) || "start", skill: Map.get(props, :skill, 1)]

    [
      %{
        id: :quake,
        name: "Quake",
        world: {Game, [hz: 60, game_opts: game_opts]},
        players: 0,
        humans: []
      }
    ]
  end

  @impl true
  def scene(view), do: scene(view, look())

  @impl true
  def scene(view, look) do
    opts = [menu: Map.get(look, :menu), options: Map.get(look, :options, %{})]

    %{
      focus: {0.0, 0.0},
      bounds: :unbounded,
      cell: fn _cell -> nil end,
      movers: [],
      picture: fn size, aspect -> Render.picture(view, size, aspect, opts) end,
      gpu: Gpu.scene(view, opts)
    }
  end

  @impl true
  def hud(_view), do: []

  @impl true
  def listener(%{camera: %{origin: {x, y, _}}}),
    do: {x / View.audio_scale(), y / View.audio_scale()}

  def listener(_view), do: nil

  @impl true
  def sounds do
    fn
      {:sound, name, volume} ->
        case Assets.sound(name) do
          nil -> nil
          voice -> %{voice | gain: voice.gain * volume}
        end

      _other ->
        nil
    end
  end

  @impl true
  def music, do: []

  @impl true
  def cue(_view, _screen), do: nil

  @impl true
  def outcome(%{over: true}),
    do: %{title: "THE GAME IS OVER", lines: ["Thanks for playing."], next: :lobby}

  def outcome(_view), do: nil
end
