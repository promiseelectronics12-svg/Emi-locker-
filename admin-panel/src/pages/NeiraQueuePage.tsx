import { useState } from 'react';
import { useNeiraQueue, useSubmitNeiraReport } from '@/hooks/useApi';
import { useTwoFactorStore } from '@/stores/twoFactorStore';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { formatDate, formatDateTime } from '@/lib/utils';
import { Flag, AlertTriangle, CheckCircle, Send, ChevronLeft, ChevronRight, FileText } from 'lucide-react';

export function NeirQueuePage() {
  const [page, setPage] = useState(1);
  const [selectedItem, setSelectedItem] = useState<string | null>(null);

  const limit = 20;
  const { data, isLoading, error } = useNeiraQueue({ page, limit });
  const submitReport = useSubmitNeiraReport();
  const { open: open2FA } = useTwoFactorStore();

  const handleSubmitReport = (itemId: string) => {
    setSelectedItem(itemId);
    open2FA({
      actionDescription: 'Submit device to BTRC NEIR - this action will flag the device for regulatory reporting',
      onSuccess: () => {
        submitReport.mutate(
          { itemId, evidence: {} },
          {
            onSuccess: () => {
              setSelectedItem(null);
            },
          }
        );
      },
    });
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">NEIR Queue</h1>
        <p className="text-muted-foreground">Devices flagged for BTRC National Equipment Identity Registry reporting</p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Flag className="h-5 w-5" />
            Devices Pending NEIR Reporting
          </CardTitle>
        </CardHeader>
        <CardContent>
          {isLoading ? (
            <div className="flex items-center justify-center h-64">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
            </div>
          ) : error ? (
            <div className="flex flex-col items-center justify-center h-64 text-muted-foreground">
              <AlertTriangle className="h-12 w-12 mb-4" />
              <p>Failed to load NEIR queue</p>
            </div>
          ) : data && data.data.length > 0 ? (
            <>
              <div className="rounded-md border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Device IMEI</TableHead>
                      <TableHead>User</TableHead>
                      <TableHead>NID</TableHead>
                      <TableHead>Dealer</TableHead>
                      <TableHead>Reason</TableHead>
                      <TableHead>Created</TableHead>
                      <TableHead>Reported</TableHead>
                      <TableHead></TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {data.data.map((item) => (
                      <TableRow key={item.id}>
                        <TableCell className="font-mono text-sm">{item.imei}</TableCell>
                        <TableCell>
                          <div>
                            <p className="font-medium">{item.userName}</p>
                          </div>
                        </TableCell>
                        <TableCell>
                          <span className="font-mono text-sm">{item.userNid}</span>
                        </TableCell>
                        <TableCell>{item.dealerName}</TableCell>
                        <TableCell>
                          <Badge variant="destructive">{item.reason}</Badge>
                        </TableCell>
                        <TableCell className="text-sm">{formatDate(item.createdAt)}</TableCell>
                        <TableCell>
                          {item.reportedAt ? (
                            <div className="flex items-center gap-1 text-green-600">
                              <CheckCircle className="h-4 w-4" />
                              <span className="text-sm">{formatDateTime(item.reportedAt)}</span>
                            </div>
                          ) : (
                            <Badge variant="secondary">Pending</Badge>
                          )}
                        </TableCell>
                        <TableCell>
                          {!item.reportedAt && (
                            <Button
                              size="sm"
                              variant="default"
                              onClick={() => handleSubmitReport(item.id)}
                              disabled={submitReport.isPending}
                            >
                              <Send className="mr-2 h-4 w-4" />
                              Report to BTRC
                            </Button>
                          )}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>

              <div className="flex items-center justify-between mt-4">
                <p className="text-sm text-muted-foreground">
                  Showing {(page - 1) * limit + 1} to {Math.min(page * limit, data.total)} of {data.total} items
                </p>
                <div className="flex gap-2">
                  <Button variant="outline" size="sm" onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1}>
                    <ChevronLeft className="h-4 w-4" />
                  </Button>
                  <span className="flex items-center px-3 text-sm">Page {page} of {data.totalPages}</span>
                  <Button variant="outline" size="sm" onClick={() => setPage((p) => Math.min(data.totalPages, p + 1))} disabled={page === data.totalPages}>
                    <ChevronRight className="h-4 w-4" />
                  </Button>
                </div>
              </div>
            </>
          ) : (
            <div className="flex flex-col items-center justify-center h-64 text-muted-foreground">
              <Flag className="h-12 w-12 mb-4" />
              <p>No devices in NEIR queue</p>
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <FileText className="h-5 w-5" />
            BTRC NEIR Integration Strategy
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid gap-4 md:grid-cols-3">
            <div className="p-4 bg-muted rounded-lg">
              <div className="flex items-center gap-2 mb-2">
                <Badge variant="secondary">Phase A</Badge>
                <span className="font-medium">Deterrence</span>
              </div>
              <p className="text-sm text-muted-foreground">
                NEIR reporting clause added to user consent form as a deterrent. Customers are informed their device may be reported to BTRC if fraud is detected.
              </p>
            </div>
            <div className="p-4 bg-muted rounded-lg">
              <div className="flex items-center gap-2 mb-2">
                <Badge variant="warning">Phase B</Badge>
                <span className="font-medium">Manual Reporting</span>
              </div>
              <p className="text-sm text-muted-foreground">
                When admin confirms fraud, submit IMEI to BTRC via email to neir@btrc.gov.bd with NID evidence. Use the Report to BTRC button above.
              </p>
            </div>
            <div className="p-4 bg-muted rounded-lg">
              <div className="flex items-center gap-2 mb-2">
                <Badge variant="info">Phase C</Badge>
                <span className="font-medium">API Integration</span>
              </div>
              <p className="text-sm text-muted-foreground">
                Apply for API access when BTRC opens it for fintech and MDM partners (expected 2027 or later). Dealers registered businesses already required to register device inventory.
              </p>
            </div>
          </div>

          <div className="p-4 bg-blue-50 border border-blue-200 rounded-lg">
            <p className="text-sm text-blue-900">
              <strong>Note:</strong> BTRC NEIR does not currently have a public API for third-party fraud reporting. The NEIR portal handles registrations via email and web form, not API.
            </p>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}