// ── SudokuLab Daily Puzzle Engine ────────────────────────────────────
// Generates a deterministic daily puzzle from the date as seed.
// Same puzzle for everyone worldwide on the same day.
// No server, no database — pure JS.

const DailyPuzzle = (() => {

  // ── Seeded RNG (Mulberry32) ────────────────────────────────────────
  function rng(seed) {
    let s = seed >>> 0;
    return () => {
      s += 0x6D2B79F5;
      let t = Math.imul(s ^ s >>> 15, 1 | s);
      t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
      return ((t ^ t >>> 14) >>> 0) / 4294967296;
    };
  }

  function shuffle(arr, rand) {
    for (let i = arr.length - 1; i > 0; i--) {
      const j = Math.floor(rand() * (i + 1));
      [arr[i], arr[j]] = [arr[j], arr[i]];
    }
    return arr;
  }

  // ── Sudoku solver ─────────────────────────────────────────────────
  function candidates(board, r, c) {
    const used = new Set();
    for (let i = 0; i < 9; i++) { used.add(board[r][i]); used.add(board[i][c]); }
    const br = 3 * Math.floor(r / 3), bc = 3 * Math.floor(c / 3);
    for (let dr = 0; dr < 3; dr++) for (let dc = 0; dc < 3; dc++) used.add(board[br+dr][bc+dc]);
    return [1,2,3,4,5,6,7,8,9].filter(n => !used.has(n));
  }

  function solve(board, countOnly = false) {
    const empty = [];
    for (let r = 0; r < 9; r++) for (let c = 0; c < 9; c++) if (!board[r][c]) empty.push([r,c]);
    if (!empty.length) return 1;
    const [r, c] = empty[0];
    const cands = candidates(board, r, c);
    let count = 0;
    for (const n of cands) {
      board[r][c] = n;
      count += solve(board, countOnly);
      board[r][c] = 0;
      if (countOnly && count >= 2) return count;
    }
    return count;
  }

  // ── Generate a solved grid ─────────────────────────────────────────
  function generateSolved(rand) {
    const board = Array.from({length:9}, () => Array(9).fill(0));
    const nums = [1,2,3,4,5,6,7,8,9];
    // Fill diagonal boxes (independent of each other)
    for (let box = 0; box < 3; box++) {
      const shuffled = shuffle([...nums], rand);
      for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++)
        board[box*3+i][box*3+j] = shuffled[i*3+j];
    }
    solve(board);
    return board;
  }

  // ── Generate puzzle by removing cells ─────────────────────────────
  function generatePuzzle(seed, clueTarget) {
    const rand = rng(seed);
    const solution = generateSolved(rand);
    const puzzle = solution.map(r => [...r]);

    const cells = shuffle([...Array(81).keys()], rand);
    const toRemove = 81 - clueTarget;
    let removed = 0;

    for (const idx of cells) {
      if (removed >= toRemove) break;
      const r = Math.floor(idx / 9), c = idx % 9;
      const val = puzzle[r][c];
      puzzle[r][c] = 0;
      const test = puzzle.map(r => [...r]);
      if (solve(test, true) === 1) {
        removed++;
      } else {
        puzzle[r][c] = val;
      }
    }
    return { puzzle, solution };
  }

  // ── Difficulty schedule ────────────────────────────────────────────
  // 0=Mon 1=Tue 2=Wed 3=Thu 4=Fri 5=Sat 6=Sun
  const SCHEDULE = [
    { name: 'Easy',   clues: 45, color: '#5a9a5a' },
    { name: 'Medium', clues: 35, color: '#d4a050' },
    { name: 'Hard',   clues: 28, color: '#c87030' },
    { name: 'Medium', clues: 35, color: '#d4a050' },
    { name: 'Hard',   clues: 28, color: '#c87030' },
    { name: 'Expert', clues: 24, color: '#c85050' },
    { name: 'Easy',   clues: 45, color: '#5a9a5a' },
  ];

  // ── Date seed ─────────────────────────────────────────────────────
  function dateSeed(d) {
    return d.getFullYear() * 10000 + (d.getMonth()+1) * 100 + d.getDate();
  }

  // ── Public API ────────────────────────────────────────────────────
  function getToday() {
    const now = new Date();
    const d = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const dow = (d.getDay() + 6) % 7; // 0=Mon
    const diff = SCHEDULE[dow];
    const seed = dateSeed(d);
    const { puzzle, solution } = generatePuzzle(seed, diff.clues);
    const tomorrow = new Date(d); tomorrow.setDate(d.getDate() + 1);
    return {
      date: d,
      dateStr: d.toLocaleDateString('en-ZA', { weekday:'long', day:'numeric', month:'long', year:'numeric' }),
      difficulty: diff.name,
      color: diff.color,
      clues: diff.clues,
      puzzle,
      solution,
      tomorrow,
      seed
    };
  }

  function getCountdown(tomorrow) {
    const now = new Date();
    const ms = tomorrow - now;
    const h = Math.floor(ms / 3600000);
    const m = Math.floor((ms % 3600000) / 60000);
    const s = Math.floor((ms % 60000) / 1000);
    return `${String(h).padStart(2,'0')}:${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}`;
  }

  return { getToday, getCountdown };
})();
