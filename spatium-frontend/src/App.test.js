import { render, screen } from '@testing-library/react';
import App from './App';

test('renders the home page hero heading', () => {
  render(<App />);
  const heading = screen.getByText(/나만의 방을 꾸며보세요/i);
  expect(heading).toBeInTheDocument();
});
