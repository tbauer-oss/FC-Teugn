import app from './server';

const PORT = process.env.PORT || 4000;

app.listen(PORT, () => {
  console.log(`FC Teugn backend listening on http://localhost:${PORT}`);
});
