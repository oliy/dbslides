---------------------------------------
-- Annotated Sudoku Solver in PG SQL --
---------------------------------------

-- Solves Sudoku puzzles, through brute force search
-- Recursively tries all possible permutations of 
-- Sudoku boards starting from the input board and finds
-- solutions with out board conflicts.
--
-- The input is a string with all the numbers in column/
-- row order, if the board was treated as a 9x9 grid of 
-- numbers.  (like reading off a printed sudoku board)

-- Recurse over all permutations of potential solutions
--
-- This one isn't mine, I just annotated it:
-- (originally from https://www.postgresql.org/message-id/b1b9fac60911041518o3c5f6917r9d47b60feab76512@mail.gmail.com)

with recursive sudoku(board) AS ( 
  -- Initial Sudoku configuration
  select '53  7    6  195    98    6 8   6   34  8 3  17   2   6 6    28    419  5    8  79'

  union all
  
  -- Recursion step, fill each blank with all possible values (1-9)
  select 
    -- replace with digit
    substr(board, 1, pos-1) || digit || substr(board, pos+1)
  from (
    -- find empty position
    select board, position(' ' in board) as pos from sudoku
  ) next, (
    -- try all possible digits
    select num::text AS digit FROM generate_series(1,9) num
  ) num
  where pos > 0
  and not exists (
    -- Find invalid configurations 
    --   "loop" over all positions, finding duplicates
    select 1
    from generate_series(1,9) i
    where
      -- duplicate within each row
      num.digit = substr(board, ((pos-1)/9)*9 + i, 1)
      -- duplicate within each column
      or num.digit = substr(board, mod(pos-1, 9) - 8 + i*9, 1)
      -- duplicate within each square
      or num.digit = substr(board, mod(((pos-1)/3), 3) * 3 + ((pos-1)/27)*27 + i + ((i-1)/3)*6, 1)
  )
)
select 
  -- Show Board
     substr(board,1,3)  || '|' || substr(board,4,3)  || '|' || substr(board,7,3)  || E'\n'
  || substr(board,10,3) || '|' || substr(board,13,3) || '|' || substr(board,16,3) || E'\n'
  || substr(board,19,3) || '|' || substr(board,22,3) || '|' || substr(board,25,3) || E'\n'
  || E'---+---+---\n'
  || substr(board,28,3) || '|' || substr(board,31,3) || '|' || substr(board,34,3) || E'\n'
  || substr(board,37,3) || '|' || substr(board,40,3) || '|' || substr(board,43,3) || E'\n'
  || substr(board,46,3) || '|' || substr(board,49,3) || '|' || substr(board,52,3) || E'\n'
  || E'---+---+---\n'
  || substr(board,55,3) || '|' || substr(board,58,3) || '|' || substr(board,61,3) || E'\n'
  || substr(board,64,3) || '|' || substr(board,67,3) || '|' || substr(board,70,3) || E'\n'
  || substr(board,73,3) || '|' || substr(board,76,3) || '|' || substr(board,79,3) || E'\n'
    AS solved
from sudoku
-- only full solutions, where no blanks exist
where position(' ' in board) = 0;
