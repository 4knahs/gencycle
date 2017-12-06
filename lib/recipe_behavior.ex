defmodule GenCycle.RecipeBehavior do
  @moduledoc ~S"""
  Specification of a gencycle recipe.
  Recipes are actions to be performed on a given event.

  # Example

  For example, in init\1 one can use:

    add_recipe(state, :my-event, :my-status, GenCycle.Recipe.MyRecipe)

  to register a recipe that runs GenCycle.Recipe.MyRecipe.start when the {:my-event, :my-status} event combination occurs.

  # Detached execution

  The execution of the start method is automated by the GenCycle.on_event\3.
  Recipes run in their own tasks.
  Changes to the state are not propagated to the owner's state.

  # Pipelining recipes

  Recipes can wait on one anothers by generating their own events.
  E.g., by returning:

    {:event, :your-event, :your-message}

  and registering the recipe on that event and message/status:

    add_recipe(state, :your-event, :your-message, GenCycle.Recipe.MyRecipe)

  Two important notes:
    - The message needs to be matchable, i.e., something constant, either an atom or a string.
    - Do not generate atoms automatically since these are not garbage collected. Try to reuse atoms.

  # Passing information

  Alternatively recipes can also return a value along with the event:

    {:event, :your-event, :your-message, return-value}

  """

  @type reason :: String.t
  @type state :: Any.t
  @type event :: Atom.t
  @type message :: Any.t
  @type return :: Any.t

  @doc """
  Recipes' start method gets invoked when the event registered via GenCycle.add_recipe\4 occurs.
  The start method is executed in its own task and its state parameter is not propagated.

  Parameters:
    - state - copy of the owner's state when this got invoked.
    - event - event that triggered the start method
    - message - event message that triggered the start method
    - return - if the triggering event passed a return value, then it is passed to start via the return parameter.
                Otherwise the parameter is set as :no_return.
  """
  @callback start(state, event, message, return) :: :no_event | {:event, event, message} | {:event, event, message, return}

end
