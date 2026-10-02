export type Role = "teacher" | "student";
export type Account = { id: string; loginId: string; name: string; role: Role; mustChangePassword: boolean };
export type Pet = { id: string; speciesId: string; level: number; xp: number; stage: number; skills: string[]; createdAt: string; representative: boolean };
export type Grant = { id: string; sku: string; quantity: number; remaining: number; reference: string; note: string; createdAt: string; revoked: boolean };
export type LogEntry = { id: string; studentId: string | null; actorName: string; message: string; createdAt: string };
export type Student = Account & { pets: Pet[]; inventory: Grant[] };
export type FarmState = {
  needsSetup: boolean;
  user: Account | null;
  className: string;
  students: Student[];
  pets: Pet[];
  inventory: Grant[];
  logs: LogEntry[];
};

// POST /api/farm uses the existing classroom identity through an HttpOnly session.
// login: {role,code}; logout: {}; purchase: {sku,quantity,expectedPrice,requestId};
// choosePet: {speciesId,requestId}; useItem: {petId,sku,quantity,requestId};
// representative: {petId,requestId}; teacher actions: grant, adjustLevel, points, price, refund.
