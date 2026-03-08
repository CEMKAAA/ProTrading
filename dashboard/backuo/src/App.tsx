import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import Layout from './components/Layout';
import Dashboard from './pages/Dashboard';
import Backtests from './pages/Backtests';
import BacktestDetail from './pages/BacktestDetail';
import Configurations from './pages/Configurations';
import NewConfiguration from './pages/NewConfiguration';
import LiveTrading from './pages/LiveTrading';

function App() {
  return (
    <BrowserRouter>
      <Layout>
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/backtests" element={<Backtests />} />
          <Route path="/backtests/:resultId" element={<BacktestDetail />} />
          <Route path="/configurations" element={<Configurations />} />
          <Route path="/configurations/new" element={<NewConfiguration />} />
          <Route path="/configurations/:configId/edit" element={<NewConfiguration />} />
          <Route path="/live" element={<LiveTrading />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </Layout>
    </BrowserRouter>
  );
}

export default App;
