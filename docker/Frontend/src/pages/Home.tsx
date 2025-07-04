import React from 'react';
import Upload from '../components/Upload';
import Ask from '../components/Ask';
import ModelSelector from '../components/ModelSelector';
import Answer from '../components/Answer';

export default function Home() {
  return (
    <div className="p-8 space-y-4">
      <h1 className="text-2xl font-bold">KI-Frontend</h1>
      <ModelSelector />
      <Upload />
      <Ask />
      <Answer />
    </div>
  );
}
