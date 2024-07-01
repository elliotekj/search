defmodule Search.DocumentExistsError do
  @moduledoc """
  Raised when a document already exists in the index.
  """

  defexception message: "Document already exists in the index."
end

defmodule Search.DocumentNotExistsError do
  @moduledoc """
  Raised when a document does not exist in the index.
  """

  defexception message: "Document does not exist in the index."
end

defmodule Search.DocumentMutatedError do
  @moduledoc """
  Raised when a document has been mutated since it was added to the index.
  """

  defexception message: "Document has been mutated; removing it will corrupt the index."
end

defmodule Search.DocumentMissingIdError do
  @moduledoc """
  Raised when a document is missing an ID.
  """

  defexception message: "Document is missing an ID."
end

defmodule Search.DocumentFieldNotString do
  @moduledoc """
  Raised when a document field does not implement String.Chars.
  """

  defexception message: "Document field does not implement String.Chars."
end
