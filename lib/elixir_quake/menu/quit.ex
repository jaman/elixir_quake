defmodule ElixirQuake.Menu.Quit do
  @moduledoc """
  The messages Quake asks "are you sure?" with when the player quits, four lines of up
  to 24 characters each, from id Software's `menu.c`.

      ElixirQuake.Menu.Quit.message(3)
  """

  @messages {
    {"  Are you gonna quit    ", "  this game just like   ", "   everything else?     ",
     "                        "},
    {" Milord, methinks that  ", "   thou art a lowly     ", " quitter. Is this true? ",
     "                        "},
    {" Do I need to bust your ", "  face open for trying  ", "        to quit?        ",
     "                        "},
    {" Man, I oughta smack you", "   for trying to quit!  ", "     Press Y to get     ",
     "      smacked out.      "},
    {" Press Y to quit like a ", "   big loser in life.   ", "  Press N to stay proud ",
     "    and successful!     "},
    {"   If you press Y to    ", "  quit, I will summon   ", "  Satan all over your   ",
     "      hard drive!       "},
    {"  Um, Asmodeus dislikes ", " his children trying to ", " quit. Press Y to return",
     "   to your Tinkertoys.  "},
    {"  If you quit now, I'll ", "  throw a blanket-party ", "   for you next time!   ",
     "                        "}
  }

  @doc "How many messages there are."
  @spec count() :: pos_integer()
  def count, do: tuple_size(@messages)

  @doc "Message number `n`, wrapping, as its four lines."
  @spec message(non_neg_integer()) :: [String.t()]
  def message(n), do: Tuple.to_list(elem(@messages, rem(n, tuple_size(@messages))))
end
